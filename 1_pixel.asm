; ================================================================
; Démo C64 : un point en mode BITMAP haute résolution (320x200)
; Version commentée en détail à but pédagogique
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o pixel.prg pixel.asm
; ================================================================
;
; --- LE PROBLÈME QU'ON RÉSOUT ---
; Le C64 démarre en mode TEXTE : l'écran est une grille de 40x25
; caractères. On ne peut pas "allumer un pixel" directement, on ne
; peut qu'afficher des caractères (lettres, symboles, blocs...).
;
; Pour dessiner un vrai pixel individuel, il faut basculer le VIC-II
; (la puce vidéo) en MODE BITMAP. Dans ce mode, l'écran devient une
; grille de 320x200 points, chacun contrôlable indépendamment.
;
; Le prix à payer : il faut gérer soi-même la mémoire vidéo, qui est
; organisée d'une façon un peu particulière (expliquée plus bas).
; ================================================================

* = $0801   ; adresse standard où le C64 attend un programme BASIC

!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00
; Ces 13 octets sont un mini-programme BASIC caché, équivalent à
; taper "10 SYS 2064" à la main. C'est ce qui permet à LOAD+RUN (ou
; l'autostart de VICE) de sauter directement dans notre code machine,
; qui commence à l'adresse 2064 décimal = $0810 en hexadécimal.

* = $0810   ; notre code machine commence ici

; ================================================================
; ADRESSES DES REGISTRES MATÉRIELS UTILISÉS
; ================================================================
; Le 6502 ne fait pas de différence entre "mémoire" et "registres
; matériels" : la puce VIC-II (vidéo) et les puces CIA (E/S) sont
; simplement branchées sur certaines adresses mémoire. Écrire à ces
; adresses avec STA revient à configurer le matériel directement.

CIA2PRA     = $dd00     ; port A de la 2e puce CIA : entre autres,
                         ; ses 2 bits de poids faible choisissent
                         ; quelle "banque" de 16 Ko de RAM le VIC-II
                         ; regarde pour trouver ses données vidéo
                         ; (le VIC-II ne voit pas toute la RAM à la
                         ; fois, seulement 16 Ko à la fois)

D011        = $d011     ; registre de contrôle vidéo n°1 du VIC-II :
                         ; contient entre autres le bit qui active
                         ; le mode bitmap (BMM)

D016        = $d016     ; registre de contrôle vidéo n°2 du VIC-II :
                         ; contient entre autres le bit "multicolore"
                         ; qu'on veut laisser désactivé ici

D018        = $d018     ; registre qui indique au VIC-II où trouver,
                         ; DANS LA BANQUE SÉLECTIONNÉE, la matrice
                         ; écran et les données bitmap

BORDER      = $d020     ; couleur de la bordure de l'écran
BACKGR      = $d021     ; couleur de fond (utilisée en mode texte ;
                         ; en bitmap, chaque bloc a ses propres
                         ; couleurs, voir plus bas)

; ================================================================
; ORGANISATION DE LA MÉMOIRE VIDÉO EN MODE BITMAP
; ================================================================
; Le mode bitmap divise l'écran (320x200 pixels) en une grille de
; 40 colonnes x 25 lignes de blocs de 8x8 pixels — les mêmes
; dimensions que la grille de caractères en mode texte !
;
; Deux zones de mémoire distinctes sont utilisées :
;
; 1) La "matrice écran" (SCREENBASE, comme en mode texte) : mais ici
;    elle ne contient PAS des caractères. Chaque octet donne les
;    DEUX couleurs du bloc 8x8 correspondant :
;       - le nibble haut (4 bits de poids fort) = couleur des pixels
;         "allumés" (bit à 1) de ce bloc
;       - le nibble bas (4 bits de poids faible) = couleur des
;         pixels "éteints" (bit à 0) de ce bloc
;    Un bloc 8x8 ne peut donc avoir que 2 couleurs à la fois.
;
; 2) La "zone bitmap" (BITMAPBASE) contient les pixels eux-mêmes,
;    1 bit par pixel. Pour chaque bloc de 8x8, on trouve 8 octets
;    CONSÉCUTIFS : le 1er octet = ligne du haut du bloc (8 pixels),
;    le 2e octet = ligne suivante, etc. jusqu'à la 8e ligne.
;    Ce n'est PAS un simple balayage ligne par ligne de tout
;    l'écran : c'est bloc par bloc, puis ligne par ligne DANS
;    chaque bloc. C'est le piège classique du mode bitmap C64.

SCREENBASE  = $0400     ; on réutilise l'adresse écran habituelle
BITMAPBASE  = $2000     ; zone bitmap : 8000 octets utiles
                         ; (320x200 / 8 = 8000), on réserve 8192
                         ; (8 Ko) par commodité d'adressage

; ================================================================
; COORDONNÉES DU POINT À AFFICHER
; ================================================================
; X va de 0 (bord gauche) à 319 (bord droit)
; Y va de 0 (haut) à 199 (bas)

POSX = 160
POSY = 100

FGCOLOR = 1              ; couleur du pixel allumé (1 = blanc)
BGCOLOR = 0              ; couleur du fond du bloc (0 = noir)
; Table des couleurs C64 : 0 noir, 1 blanc, 2 rouge, 3 cyan,
; 4 violet, 5 vert, 6 bleu, 7 jaune, 8 orange, 9 marron,
; 10 rouge clair, 11 gris foncé, 12 gris, 13 vert clair,
; 14 bleu clair, 15 gris clair

; ----------------------------------------------------------------
; Conversion coordonnées -> adresses mémoire
;
; Tout ce bloc est calculé PAR L'ASSEMBLEUR au moment de la
; compilation (ce sont des constantes, pas des instructions). Le
; 6502 n'a donc rien à calculer lui-même au moment de l'exécution :
; pas de division, pas de multiplication à faire tourner sur la
; puce, juste des adresses toutes prêtes glissées dans le code.
; C'est une technique très courante en assembleur C64 pour
; économiser du temps processeur.
; ----------------------------------------------------------------

COL       = POSX/8       ; dans quelle colonne de blocs (0-39) ?
ROW       = POSY/8       ; dans quelle ligne de blocs (0-24) ?
XREM      = POSX-(COL*8) ; position du pixel DANS le bloc, en X (0-7)
YREM      = POSY-(ROW*8) ; position du pixel DANS le bloc, en Y (0-7)

; Numéro du bloc dans la grille 40x25, en comptant ligne par ligne :
; BLOC = ROW*40 + COL

; Adresse de l'octet bitmap à modifier : on saute jusqu'au bloc
; concerné (8 octets par bloc), puis on descend de YREM lignes
; à l'intérieur du bloc :
BMOFFSET  = (ROW*40+COL)*8+YREM

; Adresse (relative) dans la matrice écran : un octet par bloc,
; donc simplement le numéro du bloc :
SCROFFSET = ROW*40+COL

; ================================================================
; VARIABLES EN PAGE ZÉRO
; ================================================================
; La "page zéro" ($00-$FF) est une zone spéciale du 6502 : les
; instructions qui l'utilisent sont plus courtes et plus rapides.
; On s'en sert ici comme pointeur 16 bits (2 octets) pour balayer
; de grandes zones mémoire avec l'adressage indirect indexé "(ptr),Y".

ptrlo = $fb              ; octet de poids faible du pointeur
ptrhi = $fc              ; octet de poids fort du pointeur

; ================================================================
; DÉBUT DU PROGRAMME
; ================================================================
start:
        sei              ; désactive les interruptions le temps de
                          ; la configuration, pour éviter qu'une
                          ; interruption ne vienne lire du matériel
                          ; vidéo à moitié configuré

        ; ------------------------------------------------------------
        ; Étape 1 : choisir la banque mémoire vue par le VIC-II
        ; ------------------------------------------------------------
        ; Le VIC-II ne peut regarder que 16 Ko de RAM à la fois parmi
        ; les 64 Ko du C64. Les 2 bits de poids faible du port A de
        ; la CIA2 choisissent laquelle. On force ces 2 bits à 1, ce
        ; qui sélectionne la banque 0 ($0000-$3FFF) — c'est déjà la
        ; valeur par défaut au démarrage, mais on le fait explicitement
        ; pour que le programme soit fiable même si autre chose avait
        ; changé ce réglage avant.
        lda CIA2PRA
        ora #%00000011   ; met les 2 bits de poids faible à 1
        sta CIA2PRA

        ; ------------------------------------------------------------
        ; Étape 2 : effacer la zone bitmap (mettre tous les pixels
        ; à "éteint", sinon on affiche les anciennes données restées
        ; en mémoire = un écran plein de "neige" aléatoire)
        ; ------------------------------------------------------------
        ; On veut écrire un octet $00 sur 8192 octets consécutifs.
        ; Un registre 6502 (X ou Y) ne compte que de 0 à 255, donc on
        ; ne peut pas balayer 8192 octets avec un seul compteur.
        ; Solution classique : une boucle interne de 256 octets
        ; (Y de 0 à 255, qui revient à 0 après 255 → c'est le "bne"
        ; qui détecte ce retour à zéro), répétée 32 fois via X
        ; (32 x 256 = 8192), en augmentant à chaque fois l'octet de
        ; poids fort du pointeur (donc en avançant de 256 octets,
        ; c'est-à-dire "d'une page mémoire").

        lda #<BITMAPBASE ; "<" = octet de poids FAIBLE de l'adresse
        sta ptrlo
        lda #>BITMAPBASE ; ">" = octet de poids FORT de l'adresse
        sta ptrhi
        ldx #32          ; compteur de pages : 32 x 256 = 8192 octets
        lda #$00         ; la valeur à écrire partout : bit à 0 = pixel éteint
clrbm:
        ldy #$00
clrbmloop:
        sta (ptrlo),y    ; écrit A à l'adresse (ptrlo/ptrhi) + Y
        iny
        bne clrbmloop    ; boucle tant que Y n'est pas revenu à 0
        inc ptrhi        ; passe à la page mémoire suivante (+256)
        dex
        bne clrbm        ; répète tant qu'il reste des pages à faire

        ; ------------------------------------------------------------
        ; Étape 3 : effacer la matrice écran (les couleurs des blocs)
        ; ------------------------------------------------------------
        ; Même technique que l'étape 2, mais sur 1024 octets (4 pages)
        ; et avec la valeur (BGCOLOR<<4)|BGCOLOR : comme on n'a encore
        ; allumé aucun pixel nulle part, on met la même couleur de
        ; fond pour les bits à 0 ET à 1 de chaque bloc, ce qui revient
        ; à un écran uniformément noir.
        lda #<SCREENBASE
        sta ptrlo
        lda #>SCREENBASE
        sta ptrhi
        ldx #4           ; 4 x 256 = 1024 octets (la matrice écran
                          ; utile ne fait que 1000 octets, on efface
                          ; 24 octets de plus par simplicité, sans
                          ; conséquence ici car on n'utilise pas les
                          ; sprites dans cette démo)
        lda #(BGCOLOR<<4)|BGCOLOR
clrscr:
        ldy #$00
clrscrloop:
        sta (ptrlo),y
        iny
        bne clrscrloop
        inc ptrhi
        dex
        bne clrscr

        ; ------------------------------------------------------------
        ; Étape 4 : définir les couleurs du SEUL bloc qui contient
        ; notre point (les autres blocs restent noir/noir de l'étape 3)
        ; ------------------------------------------------------------
        ; nibble haut = FGCOLOR (couleur du pixel qu'on va allumer)
        ; nibble bas  = BGCOLOR (couleur du reste du bloc)
        lda #(FGCOLOR<<4)|BGCOLOR
        sta SCREENBASE+SCROFFSET
        ; SCREENBASE+SCROFFSET est calculé par l'assembleur : c'est
        ; une simple instruction STA sur une adresse fixe, connue
        ; dès la compilation.

        ; ------------------------------------------------------------
        ; Étape 5 : allumer le bit correspondant à notre pixel
        ; ------------------------------------------------------------
        ; On a calculé XREM plus haut (position horizontale du pixel
        ; DANS son bloc de 8 pixels, de 0 à 7). bittable contient les
        ; 8 motifs binaires possibles : un seul bit à 1, dont la
        ; position dépend de XREM (bit 7 = pixel le plus à gauche du
        ; bloc, bit 0 = pixel le plus à droite).
        lda bittable+XREM  ; charge le bon motif de bit (constante
                            ; connue à la compilation, donc en fait
                            ; une simple lecture à adresse fixe)
        sta BITMAPBASE+BMOFFSET  ; l'écrit au bon endroit du bitmap

        ; ------------------------------------------------------------
        ; Étape 6 : activer réellement le mode bitmap sur le VIC-II
        ; ------------------------------------------------------------
        ; Jusqu'ici on a préparé les données ; le VIC-II est encore
        ; en train d'afficher du texte. C'est seulement maintenant
        ; qu'on bascule l'affichage.

        lda D011
        ora #%00100000   ; met le bit BMM (Bit Map Mode) à 1 sans
                          ; toucher aux autres bits de ce registre
                          ; (comme DEN = écran allumé, ou YSCROLL)
        sta D011

        lda D016
        and #%11101111   ; force le bit MCM (MultiColor Mode) à 0 :
                          ; on veut du bitmap "haute résolution"
                          ; classique (2 couleurs par bloc), pas le
                          ; mode bitmap multicolore (4 couleurs par
                          ; bloc mais pixels 2x plus larges)
        sta D016

        lda #%00011000   ; indique au VIC-II où trouver la matrice
                          ; écran et le bitmap DANS la banque choisie
                          ; à l'étape 1 : bits 7-4 = 0001 pointent
                          ; vers $0400 (la matrice écran), bits 3-1 =
                          ; 100 pointent vers $2000 (le bitmap)
        sta D018

        lda #$00
        sta BORDER       ; bordure noire, pour un rendu propre
        sta BACKGR       ; (moins utile en bitmap mais anodin ici)

        ; ------------------------------------------------------------
        ; Étape 7 : figer l'affichage
        ; ------------------------------------------------------------
        ; Si on faisait "rts" ici pour revenir au BASIC, le KERNAL
        ; continuerait d'afficher "READY." et de faire clignoter le
        ; curseur — en écrivant dans la matrice écran, qui sert
        ; maintenant à autre chose (des couleurs, pas des lettres).
        ; Le résultat serait un écran qui se met à clignoter de
        ; couleurs de façon incontrôlée. Une boucle infinie évite ce
        ; problème et garde une image stable.
forever:
        jmp forever
        ; Pour revenir au BASIC depuis VICE : RUN/STOP + RESTORE,
        ; ou Reset depuis le menu de l'émulateur.

; ================================================================
; DONNÉES : les 8 motifs de bit possibles pour un pixel isolé
; ================================================================
; bittable+0 = pixel le plus à gauche du bloc (bit 7)
; bittable+7 = pixel le plus à droite du bloc (bit 0)
bittable:
        !byte %10000000,%01000000,%00100000,%00010000
        !byte %00001000,%00000100,%00000010,%00000001
