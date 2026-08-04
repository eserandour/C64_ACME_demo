; ================================================================
; Hello World en assembleur 6502/6510 pour Commodore 64
; Version commentée en détail à but pédagogique
;
; Assembleur : ACME (6502/6510)
; Compilation : acme -f cbm -o hello.prg hello.asm
; ================================================================
;
; --- L'IDÉE GÉNÉRALE ---
; Contrairement au BASIC (PRINT "HELLO WORLD"), il n'existe pas
; d'instruction "afficher du texte" en assembleur 6502. On doit
; afficher les caractères UN PAR UN, en appelant une routine du
; KERNAL (le système d'exploitation en ROM du C64) pour chacun.
; Ce programme lit donc une chaîne de caractères en mémoire,
; caractère par caractère, jusqu'à un octet spécial qui marque
; la fin, et envoie chaque caractère à cette routine.
; ================================================================

; ------------------------------------------------------------
; Point d'entrée du programme (adresse $0801)
; ------------------------------------------------------------
* = $0801  ; Directive ACME (pas une instruction 6502) :
           ; place le code qui suit à l'adresse $0801,
           ; l'adresse standard où le C64 attend le début
           ; d'un programme BASIC (utilisée par LOAD/SAVE).
           ; "*" représente le compteur d'adresse courant de
           ; l'assembleur : lui assigner une valeur revient à
           ; dire "à partir d'ici, ce que j'écris ira à cette
           ; adresse une fois chargé en mémoire".

; ------------------------------------------------------------
; En-tête BASIC minimal, équivalent à la ligne : "10 SYS 2064"
; ------------------------------------------------------------
; Pourquoi cet en-tête est nécessaire :
; Quand on tape LOAD puis RUN, le C64 exécute toujours ce qui se
; trouve à $0801 EN LE TRAITANT COMME DU BASIC, jamais directement
; comme du code machine. Il n'y a pas de raccourci "RUN en
; assembleur". La seule solution est donc de déguiser le début du
; programme en un mini-programme BASIC dont l'unique instruction
; est SYS 2064 — SYS étant la commande BASIC qui saute vers une
; adresse et exécute ce qui s'y trouve comme du code machine.
;
; Chaque octet de cette ligne correspond au format interne que le
; BASIC utilise pour stocker une ligne de programme :
;   $0c,$08   -> adresse de la ligne BASIC suivante (ici : aucune,
;                ce sera la dernière ligne, donc un pointeur vers
;                la fin du programme)
;   $0a,$00   -> numéro de la ligne, codé sur 2 octets : 10 = $000a
;   $9e       -> code interne (jeton) du mot-clé BASIC "SYS"
;   $20       -> le caractère espace (" ") entre SYS et le nombre
;   $32,$30,$36,$34 -> les chiffres "2","0","6","4" tapés en toutes
;                lettres (le BASIC les relit comme du texte, pas
;                comme un nombre binaire)
;   $00       -> marque la fin de la ligne BASIC
;   $00,$00   -> marque la fin du programme BASIC tout entier
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

; Résultat concret : un LIST sur ce mini-programme affiche
; "10 SYS 2064", et un RUN exécute cette ligne comme un SYS normal,
; qui saute en exécution machine à l'adresse 2064 (décimal) =
; $0810 (hexadécimal). C'est pour ça que notre code machine doit
; commencer précisément à $0810 juste après.

; ------------------------------------------------------------
; Code machine
; ------------------------------------------------------------
* = $0810  ; 2064 en décimal = $0810 : adresse ciblée par le
           ; SYS 2064 de l'en-tête ci-dessus. Entre $080d (fin
           ; de l'en-tête, 13 octets après $0801) et $0810, ACME
           ; insère automatiquement 3 octets de remplissage ($00)
           ; pour combler l'écart, sans aucune conséquence : ce
           ; sont juste des octets inutilisés dans le fichier
           ; final, jamais exécutés.

CHROUT = $FFD2  ; Routine KERNAL : afficher un caractère
                ; C'est une adresse fixe en ROM, la même sur tous
                ; les C64. On lui donne un caractère à afficher en
                ; le plaçant dans le registre A avant de l'appeler
                ; avec JSR (Jump to SubRoutine) : JSR saute à cette
                ; adresse en mémorisant où revenir ensuite, un peu
                ; comme un appel de fonction.

start:
        ldx #0         ; Initialise le registre X à 0. X va servir
                        ; d'INDEX : le numéro du caractère qu'on est
                        ; en train de traiter dans la chaîne (le
                        ; 1er caractère est à l'index 0, le 2e à
                        ; l'index 1, etc.)
loop:
        lda message,x  ; Charge dans A l'octet situé à l'adresse
                        ; "message + X". C'est de l'adressage
                        ; "absolu indexé" : au 1er passage (X=0),
                        ; on lit le tout premier caractère de
                        ; message ; au 2e passage (X=1), le
                        ; suivant, et ainsi de suite. C'est ce
                        ; mécanisme qui permet de parcourir toute
                        ; la chaîne avec la même instruction.

        beq done        ; BEQ = "Branch if EQual (to zero)" : si le
                        ; caractère qu'on vient de charger est 0,
                        ; on saute à "done". C'est ainsi qu'on
                        ; détecte la fin de la chaîne : le texte se
                        ; termine par un octet 0 (voir plus bas),
                        ; qui ne correspond à aucun caractère
                        ; affichable et sert donc de "marqueur de
                        ; fin" — exactement le même principe que
                        ; les chaînes terminées par '\0' en C.

        jsr CHROUT      ; Affiche le caractère actuellement dans A
                        ; en appelant la routine du KERNAL.

        inx             ; Incrémente X de 1 : on passe au caractère
                        ; suivant de la chaîne au prochain tour de
                        ; boucle.

        jmp loop        ; Retourne inconditionnellement au début de
                        ; la boucle, pour traiter le caractère
                        ; suivant. JMP est un saut simple, sans
                        ; condition, contrairement à BEQ.
done:
        rts             ; RTS = ReTurn from Subroutine. Puisque ce
                        ; programme a été lancé par un SYS depuis
                        ; le BASIC (qui fonctionne un peu comme un
                        ; JSR), RTS rend la main proprement au
                        ; BASIC plutôt que de planter la machine.
                        ; On revoit alors "READY." et le curseur
                        ; clignotant, comme après n'importe quelle
                        ; commande BASIC normale.

; ------------------------------------------------------------
; Données : la chaîne de caractères à afficher
; ------------------------------------------------------------
message:
        !text "HELLO WORLD"
        ; !text est une directive ACME qui convertit chaque
        ; caractère du texte entre guillemets en son code PETSCII
        ; correspondant (le jeu de caractères du C64, proche mais
        ; pas identique à l'ASCII), et place ces octets un par un
        ; en mémoire, à la suite les uns des autres, à partir de
        ; l'adresse "message".

        !byte 0
        ; L'octet 0 ajouté juste après le texte est le marqueur de
        ; fin de chaîne détecté par le "beq done" plus haut. Sans
        ; lui, la boucle continuerait à lire indéfiniment la
        ; mémoire après "HELLO WORLD" (du code, d'autres données,
        ; n'importe quoi), en essayant de tout afficher comme du
        ; texte, jusqu'à tomber par hasard sur un octet à 0 ou
        ; planter le programme.
