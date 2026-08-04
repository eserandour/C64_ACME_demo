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

; Variables internes à drawPolygon :
polyPtr_lo  = $33        ; pointeur vers le tableau de points (entrée)
polyPtr_hi  = $34
polyN       = $35        ; nombre de sommets (entrée)
polyCount   = $36        ; compteur de tours restants
curPtr_lo   = $37        ; pointeur vers le sommet en cours de lecture
curPtr_hi   = $38
firstX_lo   = $39        ; copie du tout premier sommet, gardée de
firstX_hi   = $3a        ; côté pour fermer le polygone à la fin
firstY      = $3b

; Variables internes à drawPolygonFill :
minY        = $3c        ; ligne la plus haute du polygone
maxY        = $3d        ; ligne la plus basse du polygone
scanY       = $3e        ; ligne de balayage courante
edgeCount   = $3f        ; nombre d'intersections trouvées sur scanY
scanCount   = $40        ; compteur de boucle (réutilisé 2 fois)
edgePtr_lo  = $41        ; pointeur vers le sommet A de l'arête testée
edgePtr_hi  = $42
tmpPtr_lo   = $43        ; pointeur temporaire vers le sommet B
tmpPtr_hi   = $44
Ax_lo       = $45        ; sommet A de l'arête en cours de test
Ax_hi       = $46
Ay          = $47
Bx_lo       = $48        ; sommet B de l'arête en cours de test
Bx_hi       = $49
By          = $4a
absDx_lo    = $4b        ; |Bx-Ax|
absDx_hi    = $4c
dxSign      = $4d        ; 0 = positif, 1 = négatif
dy8         = $4e        ; By-Ay (toujours positif après normalisation)
tval        = $4f        ; scanY-Ay (multiplicande)
prod_lo     = $50        ; résultat de la multiplication
prod_hi     = $51
quot_lo     = $52        ; résultat de la division
quot_hi     = $53
remainder   = $54        ; reste de la division (inutilisé au final)
finalX_lo   = $55        ; abscisse d'intersection calculée
finalX_hi   = $56
fillIdx     = $57        ; indice de la paire d'intersections en cours
sortI       = $58        ; variables du tri par insertion
sortJ       = $59
keyLo       = $5a
keyHi       = $5b
tmpShiftLo  = $5c
tmpShiftHi  = $5d

; Variables internes à drawCircle :
circleR     = $5e        ; rayon (paramètre d'entrée)
xc_lo       = $5f        ; copie du centre (car paramX/Y seront
xc_hi       = $60        ; écrasés par putPixel à chaque point tracé)
yc          = $61
cx          = $62        ; coordonnées courantes de l'algorithme
cy          = $63        ; de Bresenham pour cercle (1/8 de tour)
dval_lo     = $64        ; paramètre de décision "d" (signé, 16 bits)
dval_hi     = $65
tmpS        = $66        ; scratch pour le calcul du delta de "d"
tmpS_hi     = $67
candX_lo    = $68        ; point candidat, avant vérification des
candX_hi    = $69        ; bornes de l'écran (peut être négatif ou
candY_lo    = $6a        ; hors écran : représentation signée 16 bits)
candY_hi    = $6b
scratch2    = $6c

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

        ; drawPolygon(triangleDemo, 3, 6) : un triangle bleu
        lda #<triangleDemo
        sta polyPtr_lo
        lda #>triangleDemo
        sta polyPtr_hi
        lda #3
        sta polyN
        lda #6
        sta paramColor
        jsr drawPolygon

        ; drawPolygonFill(quadDemo, 4, 9) : un losange plein marron
        lda #<quadDemo
        sta polyPtr_lo
        lda #>quadDemo
        sta polyPtr_hi
        lda #4
        sta polyN
        lda #9
        sta paramColor
        jsr drawPolygonFill

        ; drawCircle(160, 100, 50, 14) : un cercle bleu clair au centre
        lda #<160
        sta paramX_lo
        lda #>160
        sta paramX_hi
        lda #100
        sta paramY
        lda #50
        sta circleR
        lda #14
        sta paramColor
        jsr drawCircle

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
; 7) drawPolygon(pts, n, couleur)
; Trace le CONTOUR d'un polygone à n sommets. pts pointe vers un
; tableau de n points consécutifs en mémoire, chacun codé sur 3
; octets (x_bas, x_haut, y) — voir triangleDemo plus bas pour un
; exemple concret. Le polygone est automatiquement refermé (le
; dernier sommet est relié au premier).
;
; ASTUCE DE RÉUTILISATION : après un appel à drawLine, paramX/paramY
; contiennent exactement le point d'arrivée du segment (c'est la
; "position courante" que Bresenham fait avancer jusqu'à destination).
; On peut donc enchaîner les arêtes du polygone SANS jamais recopier
; explicitement "le point d'arrivée devient le point de départ
; suivant" : c'est déjà le cas automatiquement.
; ================================================================
drawPolygon:
        lda polyN
        cmp #2
        bcc polyDone         ; moins de 2 sommets : rien à tracer

        ; ---- lit le premier sommet, le place comme point de départ
        ; ET en garde une copie de côté pour la fermeture finale ----
        ldy #0
        lda (polyPtr_lo),y
        sta paramX_lo
        sta firstX_lo
        iny
        lda (polyPtr_lo),y
        sta paramX_hi
        sta firstX_hi
        iny
        lda (polyPtr_lo),y
        sta paramY
        sta firstY

        ; curPtr pointe vers le 2e sommet (3 octets plus loin)
        clc
        lda polyPtr_lo
        adc #3
        sta curPtr_lo
        lda polyPtr_hi
        adc #0
        sta curPtr_hi

        lda polyN
        sec
        sbc #1
        sta polyCount        ; n-1 arêtes "normales" à tracer

polyLoop:
        ldy #0
        lda (curPtr_lo),y
        sta x2_lo
        iny
        lda (curPtr_lo),y
        sta x2_hi
        iny
        lda (curPtr_lo),y
        sta y2v

        jsr drawLine          ; paramX/Y == x2/y2v après cet appel

        clc
        lda curPtr_lo
        adc #3
        sta curPtr_lo
        lda curPtr_hi
        adc #0
        sta curPtr_hi

        dec polyCount
        bne polyLoop

        ; ---- ferme le polygone : dernier sommet -> premier sommet ----
        lda firstX_lo
        sta x2_lo
        lda firstX_hi
        sta x2_hi
        lda firstY
        sta y2v
        jsr drawLine

polyDone:
        rts

; ================================================================
; 8) drawPolygonFill(pts, n, couleur)
; Remplit l'INTÉRIEUR d'un polygone à n sommets, par balayage de
; lignes (scanline fill), règle pair-impair (even-odd rule).
;
; PRINCIPE : pour chaque ligne horizontale Y qui traverse le
; polygone, on calcule où chaque arête coupe cette ligne (son
; "intersection"), on trie ces abscisses, puis on remplit entre la
; 1ère et la 2e, entre la 3e et la 4e, etc. Deux intersections
; consécutives délimitent toujours un segment INTÉRIEUR au polygone
; (c'est ce que garantit la règle pair-impair pour un contour qui ne
; se recoupe pas lui-même).
;
; Calculer une intersection demande une DIVISION (position exacte
; où l'arête croise la ligne Y), que le 6502 n'a pas câblée : voir
; mul8x16 et div16by8 plus bas, deux sous-routines génériques
; écrites pour l'occasion.
; ================================================================
drawPolygonFill:
        ; ---- étape 1 : trouve minY et maxY parmi tous les sommets ----
        lda #255
        sta minY
        lda #0
        sta maxY

        lda polyPtr_lo
        sta edgePtr_lo
        lda polyPtr_hi
        sta edgePtr_hi
        lda polyN
        sta scanCount

pf_scanMinMaxLoop:
        ldy #2
        lda (edgePtr_lo),y
        cmp minY
        bcs pf_notMin
        sta minY
pf_notMin:
        ldy #2
        lda (edgePtr_lo),y
        cmp maxY
        bcc pf_notMax
        sta maxY
pf_notMax:
        clc
        lda edgePtr_lo
        adc #3
        sta edgePtr_lo
        lda edgePtr_hi
        adc #0
        sta edgePtr_hi
        dec scanCount
        bne pf_scanMinMaxLoop

        ; ---- étape 2 : une ligne de balayage à la fois ----
        lda minY
        sta scanY

pf_scanLoop:
        lda #0
        sta edgeCount

        lda polyPtr_lo
        sta edgePtr_lo
        lda polyPtr_hi
        sta edgePtr_hi
        lda polyN
        sta scanCount

pf_edgeLoop:
        ; lit le sommet A (point courant)
        ldy #0
        lda (edgePtr_lo),y
        sta Ax_lo
        iny
        lda (edgePtr_lo),y
        sta Ax_hi
        iny
        lda (edgePtr_lo),y
        sta Ay

        ; détermine le sommet B (point suivant, ou le tout premier
        ; sommet si on est sur la dernière arête - fermeture)
        lda scanCount
        cmp #1
        bne pf_notLastEdge
        ldy #0
        lda (polyPtr_lo),y
        sta Bx_lo
        iny
        lda (polyPtr_lo),y
        sta Bx_hi
        iny
        lda (polyPtr_lo),y
        sta By
        jmp pf_gotB
pf_notLastEdge:
        clc
        lda edgePtr_lo
        adc #3
        sta tmpPtr_lo
        lda edgePtr_hi
        adc #0
        sta tmpPtr_hi
        ldy #0
        lda (tmpPtr_lo),y
        sta Bx_lo
        iny
        lda (tmpPtr_lo),y
        sta Bx_hi
        iny
        lda (tmpPtr_lo),y
        sta By
pf_gotB:

        ; ignore les arêtes horizontales (ne coupent aucune ligne
        ; de balayage de façon utile pour le remplissage)
        lda Ay
        cmp By
        bne pf_notHorizontal
        jmp pf_skipEdge
pf_notHorizontal:

        ; normalise : on veut toujours Ay <= By, sinon on échange
        ; A et B (la formule d'intersection ne dépend pas du sens
        ; de parcours de l'arête, seule la PAIRE de points compte)
        lda Ay
        cmp By
        bcc pf_noSwap
        lda Ax_lo
        pha
        lda Bx_lo
        sta Ax_lo
        pla
        sta Bx_lo
        lda Ax_hi
        pha
        lda Bx_hi
        sta Ax_hi
        pla
        sta Bx_hi
        lda Ay
        pha
        lda By
        sta Ay
        pla
        sta By
pf_noSwap:

        ; ne garde que les arêtes qui couvrent scanY, en demi-ouvert
        ; [Ay, By) : cela évite de compter deux fois une ligne qui
        ; passe exactement par un sommet partagé par 2 arêtes
        lda scanY
        cmp Ay
        bcs pf_notBeforeA
        jmp pf_skipEdge
pf_notBeforeA:
        lda scanY
        cmp By
        bcc pf_inRange
        jmp pf_skipEdge
pf_inRange:

        ; dy8 = By-Ay (toujours positif ici, arête non horizontale
        ; et déjà normalisée)
        lda By
        sec
        sbc Ay
        sta dy8

        ; tval = scanY-Ay (le nombre de lignes descendues depuis A)
        lda scanY
        sec
        sbc Ay
        sta tval

        ; absDx/dxSign = valeur absolue et signe de (Bx-Ax), même
        ; technique que dx dans drawLine
        sec
        lda Bx_lo
        sbc Ax_lo
        sta absDx_lo
        lda Bx_hi
        sbc Ax_hi
        sta absDx_hi
        bpl pf_dxpos
        sec
        lda #0
        sbc absDx_lo
        sta absDx_lo
        lda #0
        sbc absDx_hi
        sta absDx_hi
        lda #1
        sta dxSign
        jmp pf_dxdone
pf_dxpos:
        lda #0
        sta dxSign
pf_dxdone:

        ; magnitude du déplacement en X = tval * absDx (8x16 bits)
        jsr mul8x16
        ; quotient = magnitude / dy8 (16/8 bits) = déplacement exact
        jsr div16by8

        ; x = Ax +/- quotient, selon le signe de dx
        lda dxSign
        beq pf_addcase
        sec
        lda Ax_lo
        sbc quot_lo
        sta finalX_lo
        lda Ax_hi
        sbc quot_hi
        sta finalX_hi
        jmp pf_storeX
pf_addcase:
        clc
        lda Ax_lo
        adc quot_lo
        sta finalX_lo
        lda Ax_hi
        adc quot_hi
        sta finalX_hi
pf_storeX:
        ldx edgeCount
        lda finalX_lo
        sta xIntersectLo,x
        lda finalX_hi
        sta xIntersectHi,x
        inc edgeCount

pf_skipEdge:
        clc
        lda edgePtr_lo
        adc #3
        sta edgePtr_lo
        lda edgePtr_hi
        adc #0
        sta edgePtr_hi
        dec scanCount
        beq pf_edgeLoopDone
        jmp pf_edgeLoop
pf_edgeLoopDone:

        ; ---- trie les intersections trouvées, puis remplit par
        ; paires consécutives ----
        jsr sortIntersections

        lda #0
        sta fillIdx
pf_fillPairLoop:
        lda fillIdx
        cmp edgeCount
        bcs pf_scanNext
        lda fillIdx
        clc
        adc #1
        cmp edgeCount
        bcs pf_scanNext        ; pas assez d'éléments pour une paire

        ldx fillIdx
        lda xIntersectLo,x
        sta rectX1_lo
        lda xIntersectHi,x
        sta rectX1_hi
        inx
        lda xIntersectLo,x
        sta rectX2_lo
        lda xIntersectHi,x
        sta rectX2_hi

        lda scanY
        sta currentY
        jsr fillRowFast        ; réutilise le remplissage rapide
                                 ; déjà écrit pour drawRectFill !

        lda fillIdx
        clc
        adc #2
        sta fillIdx
        jmp pf_fillPairLoop

pf_scanNext:
        lda scanY
        cmp maxY
        beq pf_polyFillDone
        inc scanY
        jmp pf_scanLoop

pf_polyFillDone:
        rts

; ----------------------------------------------------------------
; sortIntersections : tri par insertion, croissant, sur les
; edgeCount premiers éléments de xIntersectLo/Hi. Un tri simple
; suffit largement : on ne trie jamais plus de quelques sommets à
; la fois (le nombre d'intersections sur une ligne ne dépasse pas
; le nombre de sommets du polygone).
; ----------------------------------------------------------------
sortIntersections:
        lda edgeCount
        cmp #2
        bcc sortDone

        lda #1
        sta sortI
sortOuter:
        ldx sortI
        cpx edgeCount
        bcs sortDone

        lda xIntersectLo,x
        sta keyLo
        lda xIntersectHi,x
        sta keyHi

        txa
        sec
        sbc #1
        sta sortJ

sortInner:
        lda sortJ
        cmp #$ff
        beq sortInsert
        ldx sortJ
        lda xIntersectHi,x
        cmp keyHi
        bcc sortInsert
        bne shiftIt
        lda xIntersectLo,x
        cmp keyLo
        bcc sortInsert
shiftIt:
        ldx sortJ
        lda xIntersectLo,x
        sta tmpShiftLo
        lda xIntersectHi,x
        sta tmpShiftHi
        inx
        lda tmpShiftLo
        sta xIntersectLo,x
        lda tmpShiftHi
        sta xIntersectHi,x
        dec sortJ
        jmp sortInner

sortInsert:
        lda sortJ
        clc
        adc #1
        tax
        lda keyLo
        sta xIntersectLo,x
        lda keyHi
        sta xIntersectHi,x

        inc sortI
        jmp sortOuter

sortDone:
        rts

; ----------------------------------------------------------------
; mul8x16 : multiplication 8 bits x 16 bits -> 16 bits
; Entrée : tval (8 bits), absDx_lo/hi (16 bits)
; Sortie : prod_lo/hi (16 bits)
; ATTENTION : détruit tval et absDx_lo/hi (utilisés comme registres
; de travail pendant le calcul, décalés bit par bit)
;
; Principe (multiplication "à la main", comme au collège, mais en
; binaire) : pour chaque bit de tval, s'il vaut 1, on ajoute
; absDx (décalé à la bonne position) au résultat, puis on double
; absDx à chaque tour pour préparer le bit suivant. Le 6502 n'a pas
; de MUL câblée : cette technique par décalages/additions est la
; façon standard de multiplier en assembleur 6502.
; ----------------------------------------------------------------
mul8x16:
        lda #0
        sta prod_lo
        sta prod_hi
        ldx #8
mul_loop:
        lsr tval
        bcc mul_skip
        clc
        lda prod_lo
        adc absDx_lo
        sta prod_lo
        lda prod_hi
        adc absDx_hi
        sta prod_hi
mul_skip:
        asl absDx_lo
        rol absDx_hi
        dex
        bne mul_loop
        rts

; ----------------------------------------------------------------
; div16by8 : division 16 bits / 8 bits -> quotient 16 bits
; Entrée : prod_lo/hi (dividende, 16 bits), dy8 (diviseur, 8 bits)
; Sortie : quot_lo/hi (quotient, 16 bits) ; le reste n'est pas
; conservé (on n'en a pas besoin ici)
;
; Principe : division binaire "posée", bit par bit (16 tours, un
; par bit du dividende). C'est l'algorithme standard de division
; restauratrice utilisé en assembleur 6502, faute d'instruction DIV.
; ----------------------------------------------------------------
div16by8:
        lda #0
        sta quot_lo
        sta quot_hi
        sta remainder
        ldx #16
divloop:
        asl prod_lo
        rol prod_hi
        rol remainder
        lda remainder
        cmp dy8
        bcc div_skip
        sbc dy8
        sta remainder
        sec
        jmp div_setbit
div_skip:
        clc
div_setbit:
        rol quot_lo
        rol quot_hi
        dex
        bne divloop
        rts

; ================================================================
; 9) drawCircle(xc, yc, r, couleur)
; Trace le CONTOUR d'un cercle de centre (xc,yc) et de rayon r.
; Paramètres : paramX/paramY = centre, circleR = rayon, paramColor.
;
; PRINCIPE (algorithme de Bresenham pour cercle, dit "midpoint
; circle") : grâce à la symétrie parfaite d'un cercle, il suffit de
; calculer UN SEUL huitième de sa courbe (le premier octant), les 7
; autres s'en déduisent directement par symétrie miroir. On avance
; un paramètre de décision "d" qui indique, à chaque pas en X, s'il
; faut aussi avancer d'un pas en Y pour rester au plus près du vrai
; cercle mathématique — exactement le même esprit que Bresenham
; pour les droites, mais avec une formule de décision différente.
;
; CLIPPING : contrairement à putPixel qui suppose des coordonnées
; toujours valides, un cercle peut déborder de l'écran (centre près
; d'un bord, ou rayon trop grand). plotClipped vérifie chaque point
; avant de l'envoyer à putPixel, et l'ignore silencieusement s'il
; tombe hors de l'écran (0-319 en X, 0-199 en Y).
; ================================================================
drawCircle:
        lda paramX_lo
        sta xc_lo
        lda paramX_hi
        sta xc_hi
        lda paramY
        sta yc

        lda #0
        sta cx
        lda circleR
        sta cy

        ; d = 1 - r  (soustraction 16 bits signée)
        sec
        lda #1
        sbc circleR
        sta dval_lo
        lda #0
        sbc #0
        sta dval_hi

circleLoop:
        ; boucle tant que cx <= cy (un seul huitième de tour)
        lda cx
        cmp cy
        beq circleContinue
        bcc circleContinue
        jmp circleDone
circleContinue:

        jsr plotCirclePoints

        inc cx

        lda dval_hi
        bmi circle_dneg

        ; d >= 0 : on avance aussi en Y, et on recalcule d en
        ; conséquence (delta = 2*(cx-cy)+1)
        dec cy
        sec
        lda cx
        sbc cy
        sta tmpS
        bmi circle_tneg1
        lda #0
        sta tmpS_hi
        jmp circle_textended1
circle_tneg1:
        lda #$ff
        sta tmpS_hi
circle_textended1:
        asl tmpS
        rol tmpS_hi
        clc
        lda tmpS
        adc #1
        sta tmpS
        lda tmpS_hi
        adc #0
        sta tmpS_hi
        clc
        lda dval_lo
        adc tmpS
        sta dval_lo
        lda dval_hi
        adc tmpS_hi
        sta dval_hi
        jmp circleLoopEnd

circle_dneg:
        ; d < 0 : delta = 2*cx+1 (toujours positif ici, cx>=1)
        lda cx
        sta tmpS
        lda #0
        sta tmpS_hi
        asl tmpS
        rol tmpS_hi
        clc
        lda tmpS
        adc #1
        sta tmpS
        lda tmpS_hi
        adc #0
        sta tmpS_hi
        clc
        lda dval_lo
        adc tmpS
        sta dval_lo
        lda dval_hi
        adc tmpS_hi
        sta dval_hi

circleLoopEnd:
        jmp circleLoop

circleDone:
        rts

; ----------------------------------------------------------------
; plotCirclePoints : trace les 8 points symétriques correspondant
; à la position courante (cx,cy) de l'algorithme
; ----------------------------------------------------------------
plotCirclePoints:
        lda cx
        jsr addToXC
        lda cy
        jsr addToYC
        jsr plotClipped

        lda cx
        jsr subFromXC
        lda cy
        jsr addToYC
        jsr plotClipped

        lda cx
        jsr addToXC
        lda cy
        jsr subFromYC
        jsr plotClipped

        lda cx
        jsr subFromXC
        lda cy
        jsr subFromYC
        jsr plotClipped

        lda cy
        jsr addToXC
        lda cx
        jsr addToYC
        jsr plotClipped

        lda cy
        jsr subFromXC
        lda cx
        jsr addToYC
        jsr plotClipped

        lda cy
        jsr addToXC
        lda cx
        jsr subFromYC
        jsr plotClipped

        lda cy
        jsr subFromXC
        lda cx
        jsr subFromYC
        jsr plotClipped

        rts

; ----------------------------------------------------------------
; addToXC / subFromXC / addToYC / subFromYC :
; A = décalage (toujours positif, 0-199) -> résultat dans
; candX_lo/hi ou candY_lo/hi (16 bits signés, avant clipping)
; ----------------------------------------------------------------
addToXC:
        sta scratch2
        clc
        lda xc_lo
        adc scratch2
        sta candX_lo
        lda xc_hi
        adc #0
        sta candX_hi
        rts

subFromXC:
        sta scratch2
        sec
        lda xc_lo
        sbc scratch2
        sta candX_lo
        lda xc_hi
        sbc #0
        sta candX_hi
        rts

addToYC:
        sta scratch2
        clc
        lda yc
        adc scratch2
        sta candY_lo
        lda #0
        adc #0
        sta candY_hi
        rts

subFromYC:
        sta scratch2
        sec
        lda yc
        sbc scratch2
        sta candY_lo
        lda #0
        sbc #0
        sta candY_hi
        rts

; ----------------------------------------------------------------
; plotClipped : appelle putPixel(candX,candY,paramColor) SEULEMENT
; si le point tombe dans l'écran (0<=X<=319, 0<=Y<=199). Sinon,
; ignore silencieusement le point (pas de crash, pas d'écriture
; hors du bitmap).
; ----------------------------------------------------------------
plotClipped:
        lda candX_hi
        bmi pc_outOfRange       ; X négatif -> hors écran
        sec
        lda candX_lo
        sbc #<320
        lda candX_hi
        sbc #>320
        bcs pc_outOfRange       ; X >= 320 -> hors écran

        lda candY_hi
        bmi pc_outOfRange       ; Y négatif -> hors écran
        sec
        lda candY_lo
        sbc #<200
        lda candY_hi
        sbc #>200
        bcs pc_outOfRange       ; Y >= 200 -> hors écran

        lda candX_lo
        sta paramX_lo
        lda candX_hi
        sta paramX_hi
        lda candY_lo
        sta paramY
        jsr putPixel            ; paramColor déjà positionné par
                                 ; l'appelant, inchangé par putPixel
pc_outOfRange:
        rts

; ================================================================
; Table des 8 positions de bit possibles dans un octet bitmap
; (utilisée par putPixel et getPixel)
; ================================================================; ================================================================
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

; ================================================================
; Données de démonstration pour drawPolygon : un triangle.
; Format : n points consécutifs, chacun sur 3 octets
; (x_bas, x_haut, y) — voir !word/!byte ci-dessous.
; ================================================================
triangleDemo:
        !word 200
        !byte 120
        !word 240
        !byte 180
        !word 160
        !byte 180

; Losange (quadrilatère), pour démontrer drawPolygonFill
quadDemo:
        !word 100
        !byte 120
        !word 130
        !byte 150
        !word 100
        !byte 180
        !word 70
        !byte 150

; Tableaux de travail pour drawPolygonFill : abscisses des
; intersections trouvées sur la ligne de balayage en cours. 16
; entrées suffisent largement pour les polygones de cette démo
; (le nombre d'intersections ne dépasse jamais le nombre de sommets).
xIntersectLo:
        !fill 16, 0
xIntersectHi:
        !fill 16, 0
