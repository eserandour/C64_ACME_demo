; ============================================================
; Assembleur 6502/6510 pour Commodore 64
; Compilation : acme -f cbm -o hello.prg hello.asm
; ============================================================

; ------------------------------------------------------------
; Point d'entrée du programme (adresse $0801)
; ------------------------------------------------------------

* = $0801  ; Directive ACME (pas une instruction 6502) :
           ; place le code qui suit à l'adresse $0801,
           ; l'adresse standard où le C64 attend le début
           ; d'un programme BASIC (utilisée par LOAD/SAVE).

; ------------------------------------------------------------
; En-tête BASIC minimal, équivalent à la ligne : "10 SYS 2064"
; ------------------------------------------------------------

!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00
            
; Résultat : un LIST sur ce mini-programme affiche "10 SYS 2064", et un RUN
; exécute cette ligne comme un SYS normal, qui saute en exécution machine
; à l'adresse 2064 (décimal) = $0810 (hexadécimal).

; ------------------------------------------------------------
; Code machine
; ------------------------------------------------------------

* = $0810  ; 2064 en décimal = $0810 : adresse ciblée par le
           ; SYS 2064 de l'en-tête ci-dessus. Entre $080d (fin
           ; de l'en-tête) et $0810, ACME insère automatiquement
           ; des octets de remplissage ($00), sans conséquence.

CHROUT = $FFD2  ; Routine KERNAL : afficher caractère

start:
        ldx #0         ; Initialise l'index x dans la chaine
loop:
        lda message,x  ; Charge le caractère
        beq done       ; Si caractère = 0, fin de chaîne
        jsr CHROUT     ; Affiche le caractère
        inx            ; Passe au caractère suivant
        jmp loop       ; Boucle
done:
        rts            ; Retour au BASIC

; ------------------------------------------------------------
; Données : la chaîne de caractères à afficher
; ------------------------------------------------------------

message:
        !text "HELLO WORLD"
        !byte 0
