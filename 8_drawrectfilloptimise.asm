; ================================================================
; Bibliothèque graphique C64 - graphics.asm
; Fonctions rangées dans le MÊME ORDRE que graphics.h (mode 13h) :
;   clearScreen -> putPixel -> getPixel -> drawLine -> (à suivre :
;   drawRect, drawRectFill, drawPolygon, drawPolygonFill,
;   drawCircle, drawCircleFill)
;
; Une seule différence de structure avec graphics.h : initGraphics
; n'existe pas côté PC (le mode 13h s'active par un simple appel
; BIOS), alors que sur C64 il faut configurer le VIC-II nous-mêmes
; (voir pixel.asm). On la place donc avant clearScreen, comme un
; prérequis, mais elle n'a pas d'équivalent dans ta bibliothèque
; d'origine.
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o graphics.prg graphics.asm
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
; Paramètres partagés entre les fonctions (l'appelant les remplit
; avant chaque JSR, comme des arguments de fonction) :
paramX_lo   = $fb
paramX_hi   = $fc
paramY      = $fd
paramColor  = $fe

; Variables internes à putPixel / getPixel / clearScreen :
xrem        = $02
yrem        = $03
rowvar      = $04
blocklo     = $05
blockhi     = $06
ptrlo       = $07
ptrhi       = $08
scratch     = $09
scraddrlo   = $0a        ; utilisé par getPixel uniquement
scraddrhi   = $0b
bmaddrlo    = $0c        ; utilisé par getPixel uniquement
bmaddrhi    = $0d

; Variables internes à drawLine :
x2_lo       = $0e
x2_hi       = $0f
y2v         = $10
dx_lo       = $11
dx_hi       = $12
dy_lo       = $13
dy_hi       = $14
sx_lo       = $15
sx_hi       = $16
sy          = $17
err_lo      = $18
err_hi      = $19
e2_lo       = $1a
e2_hi       = $1b
tmp2_lo     = $1c
tmp2_hi     = $1d

; Variables internes à drawRect : on garde une copie des 4 coins
; car paramX_lo/hi et paramY sont DÉTRUITS par drawLine (ils
; servent de "position courante" mise à jour à chaque pas de
; l'algorithme de Bresenham) — sans cette copie, on perdrait le
; point de départ après le premier des 4 côtés tracés.
rectX1_lo   = $1e
rectX1_hi   = $1f
rectY1      = $20
rectX2_lo   = $21
rectX2_hi   = $22
rectY2      = $23
currentY    = $24        ; ligne horizontale en cours

; Variables internes à la version optimisée de drawRectFill
; (remplissage par octet plutôt que par pixel) :
startCol    = $25        ; premier bloc de colonnes touché
startRem    = $26        ; position du pixel de départ dans ce bloc
endCol      = $27        ; dernier bloc de colonnes touché
endRem      = $28        ; position du pixel de fin dans ce bloc
maskbyte    = $29        ; motif de bits à combiner (OR) pour un bord
colcount    = $2a        ; compteur de blocs "pleins" au milieu
bmladdr_lo  = $2b        ; adresse bitmap calculée pour le bloc courant
bmladdr_hi  = $2c
scraddr2_lo = $2d        ; adresse écran calculée pour le bloc courant
scraddr2_hi = $2e
rb_lo       = $2f        ; row*40 : base du bloc de la ligne courante
rb_hi       = $30
rm_lo       = $31        ; scratch pour le calcul de rb (row*40)
rm_hi       = $32

; ================================================================
; PROGRAMME PRINCIPAL : petite démonstration des 4 fonctions
; ================================================================
start:
        sei

        lda #0
        jsr clearScreen
        jsr initGraphics

        ; putPixel(160,190,1) : un point blanc en bas au centre
        lda #<160
        sta paramX_lo
        lda #>160
        sta paramX_hi
        lda #190
        sta paramY
        lda #1
        sta paramColor
        jsr putPixel

        ; getPixel(160,190) -> recopié dans la bordure pour vérifier
        lda #<160
        sta paramX_lo
        lda #>160
        sta paramX_hi
        lda #190
        sta paramY
        jsr getPixel
        sta $d020

        ; drawLine(20,20, 300,180, 5) : grande diagonale verte
        lda #<20
        sta paramX_lo
        lda #>20
        sta paramX_hi
        lda #20
        sta paramY
        lda #<300
        sta x2_lo
        lda #>300
        sta x2_hi
        lda #180
        sta y2v
        lda #5
        sta paramColor
        jsr drawLine

        ; drawRect(50,150, 270,190, 3) : un rectangle cyan en bas
        lda #<50
        sta paramX_lo
        lda #>50
        sta paramX_hi
        lda #150
        sta paramY
        lda #<270
        sta x2_lo
        lda #>270
        sta x2_hi
        lda #190
        sta y2v
        lda #3
        sta paramColor
        jsr drawRect

        ; drawRectFill(50,30, 120,80, 4) : rectangle plein violet
        lda #<50
        sta paramX_lo
        lda #>50
        sta paramX_hi
        lda #30
        sta paramY
        lda #<120
        sta x2_lo
        lda #>120
        sta x2_hi
        lda #80
        sta y2v
        lda #4
        sta paramColor
        jsr drawRectFill

forever:
        jmp forever

; ================================================================
; initGraphics : bascule le VIC-II en mode bitmap (prérequis C64,
; pas de fonction équivalente dans graphics.h)
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
; 1) clearScreen(couleur)
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
; 2) putPixel(x, y, couleur)
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
; 3) getPixel(x, y) -> A = couleur (0-15)
; ================================================================
getPixel:
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
        sta scraddrlo
        lda blockhi
        adc #>SCREENBASE
        sta scraddrhi

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

        ldx xrem
        ldy #$00
        lda (bmaddrlo),y
        and bittable,x
        beq gp_pixelOff

gp_pixelOn:
        ldy #$00
        lda (scraddrlo),y
        lsr
        lsr
        lsr
        lsr
        rts

gp_pixelOff:
        ldy #$00
        lda (scraddrlo),y
        and #%00001111
        rts

; ================================================================
; 4) drawLine(x1, y1, x2, y2, couleur)
; ================================================================
drawLine:
        sec
        lda x2_lo
        sbc paramX_lo
        sta dx_lo
        lda x2_hi
        sbc paramX_hi
        sta dx_hi
        bpl dxpos
        sec
        lda #0
        sbc dx_lo
        sta dx_lo
        lda #0
        sbc dx_hi
        sta dx_hi
        lda #$ff
        sta sx_lo
        sta sx_hi
        jmp dxdone
dxpos:
        lda #1
        sta sx_lo
        lda #0
        sta sx_hi
dxdone:
        sec
        lda y2v
        sbc paramY
        sta dy_lo
        lda #0
        sbc #0
        sta dy_hi
        lda dy_hi
        bpl dypos
        sec
        lda #0
        sbc dy_lo
        sta dy_lo
        lda #0
        sbc dy_hi
        sta dy_hi
        lda #$ff
        sta sy
        jmp dydone
dypos:
        lda #1
        sta sy
dydone:

        sec
        lda dx_lo
        sbc dy_lo
        sta err_lo
        lda dx_hi
        sbc dy_hi
        sta err_hi

lineLoop:
        jsr putPixel

        lda paramX_lo
        cmp x2_lo
        bne notdone
        lda paramX_hi
        cmp x2_hi
        bne notdone
        lda paramY
        cmp y2v
        bne notdone
        jmp lineDone
notdone:
        lda err_lo
        asl
        sta e2_lo
        lda err_hi
        rol
        sta e2_hi

        clc
        lda e2_lo
        adc dy_lo
        sta tmp2_lo
        lda e2_hi
        adc dy_hi
        sta tmp2_hi
        lda tmp2_hi
        bmi skipA
        lda tmp2_lo
        ora tmp2_hi
        beq skipA

        sec
        lda err_lo
        sbc dy_lo
        sta err_lo
        lda err_hi
        sbc dy_hi
        sta err_hi

        clc
        lda paramX_lo
        adc sx_lo
        sta paramX_lo
        lda paramX_hi
        adc sx_hi
        sta paramX_hi
skipA:
        sec
        lda e2_lo
        sbc dx_lo
        sta tmp2_lo
        lda e2_hi
        sbc dx_hi
        sta tmp2_hi
        lda tmp2_hi
        bpl skipB

        clc
        lda err_lo
        adc dx_lo
        sta err_lo
        lda err_hi
        adc dx_hi
        sta err_hi

        lda paramY
        clc
        adc sy
        sta paramY
skipB:
        jmp lineLoop

lineDone:
        rts

; ================================================================
; 5) drawRect(x1, y1, x2, y2, couleur)
; Trace le CONTOUR d'un rectangle. (x1,y1) = coin supérieur gauche,
; (x2,y2) = coin inférieur droit. Réutilise drawLine 4 fois — aucun
; nouveau calcul géométrique, juste 4 appels bien choisis.
; ================================================================
drawRect:
        ; on sauvegarde les 4 coins avant le premier appel à
        ; drawLine, car paramX_lo/hi et paramY vont être écrasés
        ; (drawLine s'en sert comme "position courante")
        lda paramX_lo
        sta rectX1_lo
        lda paramX_hi
        sta rectX1_hi
        lda paramY
        sta rectY1
        lda x2_lo
        sta rectX2_lo
        lda x2_hi
        sta rectX2_hi
        lda y2v
        sta rectY2
        ; paramColor n'a pas besoin d'être sauvegardé : drawLine ne
        ; le modifie jamais, seulement le lire

        ; ---- côté du HAUT : (x1,y1) -> (x2,y1) ----
        lda rectX1_lo
        sta paramX_lo
        lda rectX1_hi
        sta paramX_hi
        lda rectY1
        sta paramY
        lda rectX2_lo
        sta x2_lo
        lda rectX2_hi
        sta x2_hi
        lda rectY1
        sta y2v
        jsr drawLine

        ; ---- côté du BAS : (x1,y2) -> (x2,y2) ----
        lda rectX1_lo
        sta paramX_lo
        lda rectX1_hi
        sta paramX_hi
        lda rectY2
        sta paramY
        lda rectX2_lo
        sta x2_lo
        lda rectX2_hi
        sta x2_hi
        lda rectY2
        sta y2v
        jsr drawLine

        ; ---- côté GAUCHE : (x1,y1) -> (x1,y2) ----
        lda rectX1_lo
        sta paramX_lo
        lda rectX1_hi
        sta paramX_hi
        lda rectY1
        sta paramY
        lda rectX1_lo
        sta x2_lo
        lda rectX1_hi
        sta x2_hi
        lda rectY2
        sta y2v
        jsr drawLine

        ; ---- côté DROIT : (x2,y1) -> (x2,y2) ----
        lda rectX2_lo
        sta paramX_lo
        lda rectX2_hi
        sta paramX_hi
        lda rectY1
        sta paramY
        lda rectX2_lo
        sta x2_lo
        lda rectX2_hi
        sta x2_hi
        lda rectY2
        sta y2v
        jsr drawLine

        rts

; ================================================================
; 6) drawRectFill(x1, y1, x2, y2, couleur)
; Trace un rectangle PLEIN. (x1,y1) = coin supérieur gauche,
; (x2,y2) = coin inférieur droit, x1<=x2 et y1<=y2 attendus.
;
; VERSION OPTIMISÉE : au lieu d'appeler putPixel pour chaque pixel
; (ce que fait la version simple, correcte mais lente), on traite
; chaque ligne de pixels OCTET PAR OCTET dans le bitmap :
;   - l'octet de GAUCHE et celui de DROITE de chaque ligne peuvent
;     être partiellement hors du rectangle -> on combine (OR) un
;     masque de bits avec le contenu existant, pour ne pas effacer
;     ce qu'il y avait à côté
;   - tous les octets ENTRE les deux sont ENTIÈREMENT dans le
;     rectangle -> on peut les écrire directement à $FF (8 pixels
;     d'un coup), sans même les lire d'abord
; C'est l'équivalent, sur le C64, de ce que _fmemset fait en mode
; 13h — sauf qu'on ne peut le faire qu'un octet (8 pixels) à la
; fois, jamais sur une ligne entière d'un coup, à cause de
; l'organisation "bloc par bloc" de la mémoire bitmap.
; ================================================================
drawRectFill:
        lda paramX_lo
        sta rectX1_lo
        lda paramX_hi
        sta rectX1_hi
        lda paramY
        sta rectY1
        lda x2_lo
        sta rectX2_lo
        lda x2_hi
        sta rectX2_hi
        lda y2v
        sta rectY2

        lda rectY1
        sta currentY

fillRow2:
        jsr fillRowFast
        lda currentY
        cmp rectY2
        beq fillDone2
        inc currentY
        jmp fillRow2

fillDone2:
        rts

; ----------------------------------------------------------------
; fillRowFast : remplit UNE seule ligne de pixels (Y = currentY)
; entre rectX1 et rectX2, octet par octet. Sous-routine interne.
; ----------------------------------------------------------------
fillRowFast:
        lda currentY
        lsr
        lsr
        lsr
        sta rowvar
        lda currentY
        and #%00000111
        sta yrem

        lda rectX1_lo
        sta ptrlo
        lda rectX1_hi
        sta ptrhi
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        lda ptrlo
        sta startCol
        lda rectX1_lo
        and #%00000111
        sta startRem

        lda rectX2_lo
        sta ptrlo
        lda rectX2_hi
        sta ptrhi
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        lsr ptrhi
        ror ptrlo
        lda ptrlo
        sta endCol
        lda rectX2_lo
        and #%00000111
        sta endRem

        ; rb = row*40, calculé une seule fois par ligne
        lda rowvar
        asl
        asl
        asl
        sta rm_lo
        lda #0
        sta rm_hi
        lda rm_lo
        sta rb_lo
        lda rm_hi
        sta rb_hi
        asl rb_lo
        rol rb_hi
        asl rb_lo
        rol rb_hi
        clc
        lda rb_lo
        adc rm_lo
        sta rb_lo
        lda rb_hi
        adc rm_hi
        sta rb_hi

        lda startCol
        cmp endCol
        bne multiBlock

; ================= CAS 1 : un seul octet concerné =================
        clc
        lda rb_lo
        adc startCol
        sta blocklo
        lda rb_hi
        adc #0
        sta blockhi
        jsr blockToBitmapAddr

        ldx startRem
        lda leftMaskTable,x
        sta maskbyte
        ldx endRem
        lda rightMaskTable,x
        and maskbyte
        sta maskbyte

        ldy #$00
        lda (bmladdr_lo),y
        ora maskbyte
        sta (bmladdr_lo),y

        jsr blockToScreenColor
        jmp fillRowFastDone

multiBlock:
; ============ CAS 2 : plusieurs octets concernés =============
        ; ---- octet de GAUCHE (partiel) ----
        clc
        lda rb_lo
        adc startCol
        sta blocklo
        lda rb_hi
        adc #0
        sta blockhi
        jsr blockToBitmapAddr

        ldx startRem
        lda leftMaskTable,x
        sta maskbyte
        ldy #$00
        lda (bmladdr_lo),y
        ora maskbyte
        sta (bmladdr_lo),y

        jsr blockToScreenColor

        ; ---- octets du MILIEU (entièrement dans le rectangle) ----
        lda endCol
        sec
        sbc startCol
        sec
        sbc #1
        sta colcount
        beq middleDone

        clc
        lda blocklo
        adc #1
        sta blocklo
        lda blockhi
        adc #0
        sta blockhi
        jsr blockToBitmapAddr
        jsr blockToScreenColor_setup

middleLoop:
        lda #$ff
        ldy #$00
        sta (bmladdr_lo),y

        lda (scraddr2_lo),y
        and #%00001111
        ora scratch
        sta (scraddr2_lo),y

        clc
        lda bmladdr_lo
        adc #8
        sta bmladdr_lo
        lda bmladdr_hi
        adc #0
        sta bmladdr_hi

        inc scraddr2_lo
        bne noCarryScr
        inc scraddr2_hi
noCarryScr:

        dec colcount
        bne middleLoop

middleDone:
        ; ---- octet de DROITE (partiel) ----
        clc
        lda rb_lo
        adc endCol
        sta blocklo
        lda rb_hi
        adc #0
        sta blockhi
        jsr blockToBitmapAddr

        ldx endRem
        lda rightMaskTable,x
        sta maskbyte
        ldy #$00
        lda (bmladdr_lo),y
        ora maskbyte
        sta (bmladdr_lo),y

        jsr blockToScreenColor

fillRowFastDone:
        rts

; ----------------------------------------------------------------
; blockToBitmapAddr : à partir de blocklo/blockhi et yrem, calcule
; l'adresse bitmap correspondante dans bmladdr_lo/hi
; ----------------------------------------------------------------
blockToBitmapAddr:
        lda blocklo
        sta bmladdr_lo
        lda blockhi
        sta bmladdr_hi
        asl bmladdr_lo
        rol bmladdr_hi
        asl bmladdr_lo
        rol bmladdr_hi
        asl bmladdr_lo
        rol bmladdr_hi
        lda yrem
        clc
        adc bmladdr_lo
        sta bmladdr_lo
        lda bmladdr_hi
        adc #0
        sta bmladdr_hi
        lda bmladdr_lo
        clc
        adc #<BITMAPBASE
        sta bmladdr_lo
        lda bmladdr_hi
        adc #>BITMAPBASE
        sta bmladdr_hi
        rts

; ----------------------------------------------------------------
; blockToScreenColor : met à jour le nibble de premier plan du bloc
; désigné par blocklo/blockhi, en conservant le fond existant
; ----------------------------------------------------------------
blockToScreenColor:
        lda blocklo
        clc
        adc #<SCREENBASE
        sta scraddr2_lo
        lda blockhi
        adc #>SCREENBASE
        sta scraddr2_hi

        lda paramColor
        asl
        asl
        asl
        asl
        sta scratch

        ldy #$00
        lda (scraddr2_lo),y
        and #%00001111
        ora scratch
        sta (scraddr2_lo),y
        rts

; ----------------------------------------------------------------
; blockToScreenColor_setup : même calcul que blockToScreenColor,
; mais sans écrire tout de suite (utilisé avant middleLoop, qui
; écrit elle-même à chaque tour)
; ----------------------------------------------------------------
blockToScreenColor_setup:
        lda blocklo
        clc
        adc #<SCREENBASE
        sta scraddr2_lo
        lda blockhi
        adc #>SCREENBASE
        sta scraddr2_hi

        lda paramColor
        asl
        asl
        asl
        asl
        sta scratch
        rts

; ================================================================
; Table des 8 positions de bit possibles dans un octet bitmap
; (utilisée par putPixel et getPixel)
; ================================================================
bittable:
        !byte %10000000,%01000000,%00100000,%00010000
        !byte %00001000,%00000100,%00000010,%00000001

; ================================================================
; Tables de masques pour drawRectFill : permettent de couvrir une
; PLAGE de colonnes dans un octet (pas un seul bit comme bittable)
; ================================================================
; leftMaskTable[s]  = bits couvrant les colonnes s à 7 (bord GAUCHE
;                     d'un octet partiellement dans le rectangle)
leftMaskTable:
        !byte %11111111,%01111111,%00111111,%00011111
        !byte %00001111,%00000111,%00000011,%00000001

; rightMaskTable[e] = bits couvrant les colonnes 0 à e (bord DROIT
;                     d'un octet partiellement dans le rectangle)
rightMaskTable:
        !byte %10000000,%11000000,%11100000,%11110000
        !byte %11111000,%11111100,%11111110,%11111111
