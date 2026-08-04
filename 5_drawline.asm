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
; Compilation : acme -f cbm -o drawline.prg drawline.asm
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
; Table des 8 positions de bit possibles dans un octet bitmap
; (utilisée par putPixel et getPixel)
; ================================================================
bittable:
        !byte %10000000,%01000000,%00100000,%00010000
        !byte %00001000,%00000100,%00000010,%00000001
