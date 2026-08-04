; ================================================================
; Bibliothèque graphique C64 - putPixel(x, y, couleur)
; Équivalent de putPixel() dans graphics.h (mode 13h)
;
; LA DIFFÉRENCE MAJEURE avec pixel.asm : là-bas, X et Y étaient des
; CONSTANTES (POSX=160, POSY=100), donc l'assembleur calculait tout
; à l'avance et le 6502 n'avait plus qu'à écrire un octet à une
; adresse toute prête. Ici, X et Y sont des VALEURS QUELCONQUES
; connues seulement au moment de l'exécution. Il faut donc faire
; tourner sur le 6502 les calculs que l'assembleur faisait pour
; nous jusqu'ici : division par 8, reste de division, multiplication
; par 40 — alors que le 6502 n'a NI division NI multiplication
; câblées, seulement des décalages de bits et des additions.
;
; UNE LIMITE MATÉRIELLE IMPORTANTE (différence avec le mode 13h du
; PC) : en mode 13h, chaque pixel peut avoir n'importe laquelle des
; 256 couleurs de la palette, indépendamment de ses voisins. En
; mode bitmap C64, un bloc de 8x8 pixels ne peut avoir que DEUX
; couleurs à la fois (rappel de pixel.asm : nibble haut = 1er plan,
; nibble bas = fond). Notre putPixel modifie donc la couleur de
; PREMIER PLAN du bloc entier — pas seulement du pixel demandé.
; Concrètement : si deux pixels voisins du même bloc de 8x8 reçoivent
; des couleurs différentes, le second appel "gagne" et change aussi
; la couleur du premier. C'est une vraie contrainte du matériel, pas
; un bug de ce code.
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o putpixel.prg putpixel.asm
; ================================================================

* = $0801
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00
* = $0810

; ================================================================
; Registres VIC-II / CIA2
; ================================================================
CIA2PRA     = $dd00
D011        = $d011
D016        = $d016
D018        = $d018

SCREENBASE  = $0400
BITMAPBASE  = $2000

; ================================================================
; Zero page
; ================================================================
; Paramètres d'entrée de putPixel, remplis par l'appelant avant le
; JSR — c'est notre "liste d'arguments", puisque le 6502 n'a pas de
; mécanisme de passage de paramètres par pile comme en C :
paramX_lo   = $fb        ; X, octet de poids faible (X va de 0 à 319)
paramX_hi   = $fc        ; X, octet de poids fort
paramY      = $fd        ; Y (0-199, tient sur un seul octet)
paramColor  = $fe        ; couleur (0-15)

; Variables de travail internes à putPixel (jamais utilisées par
; l'appelant, uniquement pendant le calcul) :
xrem        = $02        ; position du pixel dans son bloc, en X (0-7)
yrem        = $03        ; position du pixel dans son bloc, en Y (0-7)
rowvar      = $04        ; Y/8 : numéro de ligne de blocs (0-24)
blocklo     = $05        ; numéro de bloc dans la grille 40x25 (16 bits)
blockhi     = $06        ; -> gardé intact du début à la fin du calcul
ptrlo       = $07        ; pointeur 16 bits "jetable", réutilisé
ptrhi       = $08        ; plusieurs fois pour des calculs différents
scratch     = $09        ; une case libre supplémentaire

; ================================================================
; PROGRAMME PRINCIPAL : quelques appels de démonstration
; ================================================================
start:
        sei

        ; On efface la mémoire vidéo AVANT d'activer le mode bitmap :
        ; tant qu'on n'a pas basculé $d011, le VIC-II affiche encore
        ; du texte et personne ne regarde ce qu'il y a dans la zone
        ; bitmap/écran — on peut la préparer tranquillement.
        lda #0
        jsr clearScreen         ; fond noir uni, pendant qu'on est
                                 ; encore en mode texte (invisible)
        jsr initGraphics        ; SEULEMENT MAINTENANT on bascule
                                 ; l'affichage : tout est déjà propre

        ; ---- putPixel(160, 100, 1) : un point blanc au centre ----
        lda #<160
        sta paramX_lo
        lda #>160
        sta paramX_hi
        lda #100
        sta paramY
        lda #1
        sta paramColor
        jsr putPixel

        ; ---- putPixel(163, 100, 2) : un point rouge juste à côté,
        ; DANS LE MÊME BLOC 8x8 que le précédent (160/8=20 et
        ; 163/8=20 -> même colonne de blocs). Observe le résultat :
        ; les DEUX points apparaissent rouges, pas juste le second —
        ; c'est la limite du "2 couleurs par bloc" expliquée en haut.
        lda #<163
        sta paramX_lo
        lda #>163
        sta paramX_hi
        lda #100
        sta paramY
        lda #2
        sta paramColor
        jsr putPixel

        ; ---- putPixel(200, 50, 7) : un point jaune, dans un bloc
        ; totalement différent -> n'affecte pas les précédents.
        lda #<200
        sta paramX_lo
        lda #>200
        sta paramX_hi
        lda #50
        sta paramY
        lda #7
        sta paramColor
        jsr putPixel

forever:
        jmp forever

; ================================================================
; initGraphics : bascule le VIC-II en mode bitmap (voir pixel.asm)
; ================================================================
initGraphics:
        lda CIA2PRA
        ora #%00000011
        sta CIA2PRA
        lda D011
        ora #%00100000
        sta D011
        lda D016
        and #%11101111
        sta D016
        lda #%00011000
        sta D018
        rts

; ================================================================
; clearScreen(couleur) : efface bitmap ET matrice écran (voir
; graphics.asm pour le détail commenté du calcul (c<<4)|c)
; ================================================================
clearScreen:
        pha
        lda #<BITMAPBASE
        sta ptrlo
        lda #>BITMAPBASE
        sta ptrhi
        ldx #32
        lda #$00
cbm:
        ldy #$00
cbmloop:
        sta (ptrlo),y
        iny
        bne cbmloop
        inc ptrhi
        dex
        bne cbm

        pla
        pha
        asl
        asl
        asl
        asl
        sta scratch
        pla
        ora scratch

        pha
        lda #<SCREENBASE
        sta ptrlo
        lda #>SCREENBASE
        sta ptrhi
        pla

        ldx #4
cs:
        ldy #$00
csloop:
        sta (ptrlo),y
        iny
        bne csloop
        inc ptrhi
        dex
        bne cs
        rts

; ================================================================
; putPixel : allume le pixel (paramX, paramY) avec paramColor
; ================================================================
putPixel:
        ; ------------------------------------------------------------
        ; col = X / 8   (division par 8 = 3 décalages à droite d'un
        ; nombre 16 bits ; LSR décale l'octet de poids fort, ROR fait
        ; "entrer" le bit qui en sort dans le poids faible : c'est
        ; ainsi qu'on décale un nombre 16 bits avec des instructions
        ; qui ne travaillent que sur 8 bits à la fois)
        ; ------------------------------------------------------------
        lda paramX_lo
        sta ptrlo
        lda paramX_hi
        sta ptrhi
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        ; ptrlo = col (0-39), ptrhi = 0

        lda ptrlo
        sta blocklo             ; on démarre "bloc" avec juste "col"
        lda #0
        sta blockhi             ; pour l'instant bloc = col (row pas encore ajouté)

        ; ------------------------------------------------------------
        ; xrem = X mod 8 : comme 8 est une puissance de 2, le reste
        ; de la division par 8 est simplement les 3 bits de poids
        ; faible de X. Pas besoin de vraie division !
        ; ------------------------------------------------------------
        lda paramX_lo
        and #%00000111
        sta xrem

        ; row = Y / 8 (Y tient sur 8 bits : 3 simples LSR suffisent)
        lda paramY
        lsr
        lsr
        lsr
        sta rowvar

        ; yrem = Y mod 8, même astuce que pour X
        lda paramY
        and #%00000111
        sta yrem

        ; ------------------------------------------------------------
        ; bloc = row*40 + col
        ; Le 6502 n'a pas de multiplication câblée. On calcule row*40
        ; grâce à 40 = 32 + 8 : multiplier par 8 ou par 32 n'est
        ; qu'une histoire de décalages (x8 = 3 décalages, x32 = 5) :
        ;    row*40 = row*8 + row*32 = row*8 + (row*8)*4
        ; ------------------------------------------------------------
        lda rowvar
        asl
        asl
        asl                     ; A = row*8 (tient sur 8 bits : max 24*8=192)
        sta ptrlo
        lda #0
        sta ptrhi               ; ptrlo/ptrhi = row*8 (représenté sur 16 bits)

        lda ptrlo
        sta scratch
        lda ptrhi
        sta rowvar              ; rowvar ne sert plus à rien d'autre :
                                 ; on le réutilise comme 2e moitié
                                 ; d'un nombre 16 bits (scratch/rowvar)
        asl scratch
        rol rowvar              ; (row*8)*2 = row*16
        asl scratch
        rol rowvar              ; (row*16)*2 = row*32
        ; scratch/rowvar = row*32, ptrlo/ptrhi = row*8 (tous deux 16 bits)

        clc
        lda scratch
        adc ptrlo
        sta ptrlo
        lda rowvar
        adc ptrhi
        sta ptrhi
        ; ptrlo/ptrhi = row*40

        clc
        lda ptrlo
        adc blocklo             ; + col
        sta blocklo
        lda ptrhi
        adc blockhi
        sta blockhi
        ; blocklo/blockhi = row*40 + col = numéro de bloc final,
        ; conservé intact jusqu'à la fin de la routine

        ; ------------------------------------------------------------
        ; Couleur : met à jour le nibble de PREMIER PLAN du bloc dans
        ; la matrice écran, en conservant le nibble de FOND existant
        ; (lecture-modification-écriture : on ne veut pas effacer ce
        ; qui était déjà là)
        ; ------------------------------------------------------------
        lda blocklo
        clc
        adc #<SCREENBASE
        sta ptrlo
        lda blockhi
        adc #>SCREENBASE
        sta ptrhi
        ; ptrlo/ptrhi = adresse exacte dans la matrice écran

        lda paramColor
        asl
        asl
        asl
        asl                     ; A = couleur*16 (dans le nibble haut)
        sta scratch             ; garde ce nibble de côté

        ldy #$00
        lda (ptrlo),y           ; lit l'octet couleur ACTUEL du bloc
        and #%00001111          ; efface l'ancien nibble haut, garde
                                 ; le nibble bas (couleur de fond) intact
        ora scratch             ; combine avec le nouveau nibble haut
        sta (ptrlo),y           ; réécrit l'octet complet

        ; ------------------------------------------------------------
        ; Bitmap : allume le bit du pixel, à l'adresse
        ; BITMAPBASE + bloc*8 + yrem
        ; ------------------------------------------------------------
        lda blocklo
        sta ptrlo
        lda blockhi
        sta ptrhi
        asl ptrlo
        rol ptrhi
        asl ptrlo
        rol ptrhi
        asl ptrlo
        rol ptrhi
        ; ptrlo/ptrhi = bloc*8

        lda yrem
        clc
        adc ptrlo
        sta ptrlo
        lda ptrhi
        adc #0
        sta ptrhi
        ; ptrlo/ptrhi = bloc*8 + yrem

        lda ptrlo
        clc
        adc #<BITMAPBASE
        sta ptrlo
        lda ptrhi
        adc #>BITMAPBASE
        sta ptrhi
        ; ptrlo/ptrhi = adresse finale dans le bitmap

        ldx xrem                ; index dans bittable : quel bit allumer
        ldy #$00
        lda (ptrlo),y           ; lit l'octet bitmap ACTUEL (important :
                                 ; ne pas écraser les autres pixels déjà
                                 ; allumés dans ce même octet !)
        ora bittable,x          ; ajoute le nouveau bit sans toucher aux autres
        sta (ptrlo),y

        rts

; ================================================================
; Table des 8 positions de bit possibles dans un octet bitmap
; ================================================================
bittable:
        !byte %10000000,%01000000,%00100000,%00010000
        !byte %00001000,%00000100,%00000010,%00000001
