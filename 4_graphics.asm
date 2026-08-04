; ================================================================
; Bibliothèque graphique C64 - getPixel(x, y)
; Équivalent de getPixel() dans graphics.h (mode 13h)
;
; C'est l'opération INVERSE de putPixel : au lieu d'écrire un bit
; et un nibble de couleur, on les LIT, et on reconstruit la couleur
; du pixel demandé :
;   - si le bit du pixel dans le bitmap vaut 1 -> c'est la couleur
;     de PREMIER PLAN du bloc (nibble haut de la matrice écran)
;   - si le bit vaut 0 -> c'est la couleur de FOND du bloc
;     (nibble bas de la matrice écran)
;
; CONVENTION DE RETOUR : comme il n'y a qu'une seule valeur à
; renvoyer (contrairement aux 3 paramètres d'entrée), on utilise le
; registre A, exactement comme "return" en C place une valeur dans
; un registre au retour d'une fonction.
;
; Remarque : le calcul d'adresse (bloc, xrem, yrem...) est IDENTIQUE
; à celui de putPixel. On ne factorise pas encore ce code commun en
; une sous-routine partagée : on attend d'avoir une 3e fonction qui
; en aurait besoin (drawLine, bientôt) avant de le faire — c'est une
; habitude classique en programmation ("attendre la 3e répétition
; avant de généraliser") pour éviter de créer une abstraction avant
; de savoir exactement ce qu'elle doit couvrir.
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o getpixel.prg getpixel.asm
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
BORDER      = $d020

SCREENBASE  = $0400
BITMAPBASE  = $2000

; ================================================================
; Zero page
; ================================================================
paramX_lo   = $fb
paramX_hi   = $fc
paramY      = $fd
paramColor  = $fe        ; utilisé par putPixel/clearScreen seulement

xrem        = $02
yrem        = $03
rowvar      = $04
blocklo     = $05
blockhi     = $06
ptrlo       = $07
ptrhi       = $08
scratch     = $09
scraddrlo   = $0a         ; adresse écran calculée, gardée de côté
scraddrhi   = $0b         ; le temps de tester le bit dans le bitmap
bmaddrlo    = $0c         ; adresse bitmap calculée
bmaddrhi    = $0d

; ================================================================
; PROGRAMME PRINCIPAL : dessine un point, puis le relit avec
; getPixel pour vérifier que la couleur récupérée est la bonne.
; On affiche le résultat en le recopiant dans la couleur de la
; bordure — le seul "canal de sortie" simple disponible en mode
; bitmap, faute de pouvoir afficher du texte facilement ici.
; ================================================================
start:
        sei

        lda #0
        jsr clearScreen
        jsr initGraphics

        ; ---- putPixel(50, 50, 5) : un point vert ----
        lda #<50
        sta paramX_lo
        lda #>50
        sta paramX_hi
        lda #50
        sta paramY
        lda #5
        sta paramColor
        jsr putPixel

        ; ---- getPixel(50, 50) : on relit la couleur du même point ----
        lda #<50
        sta paramX_lo
        lda #>50
        sta paramX_hi
        lda #50
        sta paramY
        jsr getPixel
        ; A contient maintenant la couleur lue (doit valoir 5)

        sta BORDER          ; on la recopie dans la bordure : si tout
                             ; est correct, la bordure doit devenir
                             ; VERTE, la même couleur que le point

forever:
        jmp forever

; ================================================================
; initGraphics
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
; clearScreen(couleur)
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
; (identique à putpixel.asm, voir ce fichier pour les commentaires
; détaillés du calcul d'adresse)
; ================================================================
putPixel:
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
        lda ptrlo
        sta blocklo
        lda #0
        sta blockhi

        lda paramX_lo
        and #%00000111
        sta xrem

        lda paramY
        lsr
        lsr
        lsr
        sta rowvar

        lda paramY
        and #%00000111
        sta yrem

        lda rowvar
        asl
        asl
        asl
        sta ptrlo
        lda #0
        sta ptrhi

        lda ptrlo
        sta scratch
        lda ptrhi
        sta rowvar
        asl scratch
        rol rowvar
        asl scratch
        rol rowvar

        clc
        lda scratch
        adc ptrlo
        sta ptrlo
        lda rowvar
        adc ptrhi
        sta ptrhi

        clc
        lda ptrlo
        adc blocklo
        sta blocklo
        lda ptrhi
        adc blockhi
        sta blockhi

        lda blocklo
        clc
        adc #<SCREENBASE
        sta ptrlo
        lda blockhi
        adc #>SCREENBASE
        sta ptrhi

        lda paramColor
        asl
        asl
        asl
        asl
        sta scratch

        ldy #$00
        lda (ptrlo),y
        and #%00001111
        ora scratch
        sta (ptrlo),y

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

        lda yrem
        clc
        adc ptrlo
        sta ptrlo
        lda ptrhi
        adc #0
        sta ptrhi

        lda ptrlo
        clc
        adc #<BITMAPBASE
        sta ptrlo
        lda ptrhi
        adc #>BITMAPBASE
        sta ptrhi

        ldx xrem
        ldy #$00
        lda (ptrlo),y
        ora bittable,x
        sta (ptrlo),y

        rts

; ================================================================
; getPixel : lit la couleur du pixel (paramX, paramY)
; Retour : A = couleur (0-15)
; ================================================================
getPixel:
        ; ---- même calcul de bloc/xrem/yrem que putPixel ----
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
        lda ptrlo
        sta blocklo
        lda #0
        sta blockhi

        lda paramX_lo
        and #%00000111
        sta xrem

        lda paramY
        lsr
        lsr
        lsr
        sta rowvar

        lda paramY
        and #%00000111
        sta yrem

        lda rowvar
        asl
        asl
        asl
        sta ptrlo
        lda #0
        sta ptrhi

        lda ptrlo
        sta scratch
        lda ptrhi
        sta rowvar
        asl scratch
        rol rowvar
        asl scratch
        rol rowvar

        clc
        lda scratch
        adc ptrlo
        sta ptrlo
        lda rowvar
        adc ptrhi
        sta ptrhi

        clc
        lda ptrlo
        adc blocklo
        sta blocklo
        lda ptrhi
        adc blockhi
        sta blockhi
        ; blocklo/blockhi = numéro de bloc

        ; ---- adresse écran, gardée de côté dans scraddrlo/hi ----
        lda blocklo
        clc
        adc #<SCREENBASE
        sta scraddrlo
        lda blockhi
        adc #>SCREENBASE
        sta scraddrhi

        ; ---- adresse bitmap, gardée de côté dans bmaddrlo/hi ----
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

        lda yrem
        clc
        adc ptrlo
        sta ptrlo
        lda ptrhi
        adc #0
        sta ptrhi

        lda ptrlo
        clc
        adc #<BITMAPBASE
        sta bmaddrlo
        lda ptrhi
        adc #>BITMAPBASE
        sta bmaddrhi

        ; ---- teste le bit du pixel dans le bitmap ----
        ldx xrem
        ldy #$00
        lda (bmaddrlo),y
        and bittable,x        ; ne garde que le bit qui nous intéresse
        beq pixelOff           ; résultat 0 -> le bit était à 0 (éteint)

pixelOn:
        ; le pixel est allumé -> sa couleur = nibble HAUT de l'octet
        ; écran. On le ramène dans les 4 bits de poids faible avec
        ; 4 décalages à droite, pour obtenir une valeur 0-15 propre.
        ldy #$00
        lda (scraddrlo),y
        lsr
        lsr
        lsr
        lsr
        rts

pixelOff:
        ; le pixel est éteint -> sa couleur = nibble BAS de l'octet
        ; écran, déjà dans les 4 bits de poids faible : un simple
        ; masque suffit, pas besoin de décaler.
        ldy #$00
        lda (scraddrlo),y
        and #%00001111
        rts

; ================================================================
; Table des 8 positions de bit possibles dans un octet bitmap
; ================================================================
bittable:
        !byte %10000000,%01000000,%00100000,%00010000
        !byte %00001000,%00000100,%00000010,%00000001
