; ================================================================
; Bibliothèque graphique C64 - clearScreen(couleur)
; Équivalent de clearScreen() dans graphics.h (mode 13h)
;
; Différence clé avec pixel.asm : jusqu'ici, la couleur était une
; CONSTANTE connue à la compilation (FGCOLOR = 1, écrit une fois
; pour toutes dans le binaire). Ici, clearScreen devient une vraie
; SOUS-ROUTINE : on peut l'appeler plusieurs fois avec des couleurs
; différentes SANS recompiler, exactement comme en C on appelle
; clearScreen(6) puis plus tard clearScreen(0) dans le même
; programme.
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o clearscreen.prg clearscreen.asm
; ================================================================

* = $0801
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00
* = $0810

; ================================================================
; Registres VIC-II / CIA2 (voir pixel.asm pour le détail de chacun)
; ================================================================
CIA2PRA     = $dd00
D011        = $d011
D016        = $d016
D018        = $d018
BORDER      = $d020
BACKGR      = $d021

SCREENBASE  = $0400
BITMAPBASE  = $2000

; ================================================================
; Zero page : pointeur de balayage mémoire, réutilisé par toutes
; les futures fonctions de la bibliothèque (putPixel, drawLine...)
; ================================================================
ptrlo = $fb
ptrhi = $fc

; ================================================================
; PASSAGE DE PARAMÈTRE : LA CONVENTION QU'ON ADOPTE ICI
; ================================================================
; Le 6502 n'a pas de pile d'appel avec paramètres comme en C
; (pas de "clearScreen(6)" où 6 serait automatiquement empilé).
; La convention la plus simple et la plus courante en assembleur
; C64 consiste à mettre le ou les paramètres dans un registre (A,
; X ou Y) juste avant le JSR. Ici : le registre A contient la
; couleur voulue (0-15) au moment d'appeler clearScreen.
;
;   lda #6        ; le paramètre "couleur" = 6 (bleu)
;   jsr clearScreen
;
; C'est l'équivalent assembleur de l'appel C "clearScreen(6);".
; ================================================================

; ================================================================
; PROGRAMME PRINCIPAL
; ================================================================
start:
        sei

        jsr initGraphics   ; configure le VIC-II en mode bitmap
                            ; UNE SEULE FOIS (pas la peine de le
                            ; refaire à chaque clearScreen)

        lda #6              ; paramètre : couleur 6 = bleu
        jsr clearScreen     ; appel de la fonction, comme en C :
                            ; clearScreen(6);

forever:
        jmp forever         ; on fige l'affichage pour voir le
                            ; résultat (RUN/STOP+RESTORE pour sortir)

; ================================================================
; initGraphics : bascule le VIC-II en mode bitmap haute résolution
; ================================================================
; Ne prend aucun paramètre. À appeler UNE SEULE FOIS avant toute
; autre fonction de la bibliothèque. Reprend exactement la logique
; déjà expliquée en détail dans pixel.asm (étapes 1 et 6).
; ----------------------------------------------------------------
initGraphics:
        lda CIA2PRA
        ora #%00000011      ; banque VIC 0 ($0000-$3FFF)
        sta CIA2PRA

        lda D011
        ora #%00100000      ; BMM = 1 (mode bitmap)
        sta D011

        lda D016
        and #%11101111      ; MCM = 0 (pas multicolore)
        sta D016

        lda #%00011000      ; écran à $0400, bitmap à $2000
        sta D018

        rts

; ================================================================
; clearScreen : remplit tout l'écran d'une seule couleur unie
; ================================================================
; Paramètre d'entrée : A = couleur (0-15)
;
; Principe : contrairement à pixel.asm où on distinguait
; "couleur de premier plan" (bit=1) et "couleur de fond" (bit=0)
; par bloc, ici on veut un écran UNIFORME. La façon la plus simple
; d'obtenir ça : peu importe la valeur des bits dans le bitmap
; (allumés ou éteints), TOUS les blocs affichent la même couleur.
; Il suffit donc de mettre la même couleur dans le nibble haut ET
; le nibble bas de chaque octet de la matrice écran : (C<<4)|C.
; On n'a même pas besoin de toucher au contenu du bitmap lui-même.
;
; Cette routine détruit le contenu de A, X, Y (comme le ferait
; n'importe quelle fonction) : si l'appelant a besoin de préserver
; ces registres, c'est à lui de les sauvegarder avant l'appel (on
; verra cette technique — PHA/PLA — dans une prochaine étape).
; ----------------------------------------------------------------
clearScreen:
        ; --------------------------------------------------------
        ; Étape A : construire l'octet (couleur<<4)|couleur
        ; --------------------------------------------------------
        ; A contient la couleur (0-15) passée en paramètre. On la
        ; décale de 4 bits vers la gauche (ASL x4 = multiplier par
        ; 16) pour la mettre dans le nibble haut, puis on additionne
        ; la couleur d'origine pour remplir aussi le nibble bas.
        ; Exemple avec couleur = 6 ($06) :
        ;   $06 décalé 4 fois à gauche -> $60
        ;   $60 + $06 -> $66  (nibble haut = 6, nibble bas = 6)
        pha                 ; sauvegarde la couleur d'origine sur
                             ; la pile (PusH Accumulator), le temps
                             ; de calculer le décalage
        asl                 ; A = A * 2
        asl                 ; A = A * 4
        asl                 ; A = A * 8
        asl                 ; A = A * 16  (couleur dans le nibble haut)
        sta ptrlo            ; case temporaire (on réutilise ptrlo,
                             ; libre à ce stade car pas encore
                             ; utilisé comme pointeur)
        pla                 ; PuLl Accumulator : récupère la
                             ; couleur d'origine depuis la pile
        ora ptrlo            ; combine nibble haut + nibble bas
                             ; -> A = (couleur<<4)|couleur

        ; --------------------------------------------------------
        ; Étape B : remplir la matrice écran (1024 octets) avec
        ; cette valeur, avec la même technique de double boucle
        ; que dans pixel.asm (256 x 4 pages via le pointeur 16 bits
        ; ptrlo/ptrhi et l'adressage indirect indexé)
        ; --------------------------------------------------------
        pha                 ; on remet la valeur calculée sur la
                             ; pile, le temps d'initialiser le
                             ; pointeur avec A (sinon on la perdrait)
        lda #<SCREENBASE
        sta ptrlo
        lda #>SCREENBASE
        sta ptrhi
        pla                 ; récupère la valeur (couleur<<4)|couleur

        ldx #4              ; 4 pages x 256 = 1024 octets
clrscr:
        ldy #$00
clrscrloop:
        sta (ptrlo),y
        iny
        bne clrscrloop
        inc ptrhi
        dex
        bne clrscr

        rts                 ; fin de la fonction, retour à l'appelant
