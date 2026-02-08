;; ===========================================================
;; C64GPT - AI Chat Assistant for the Commodore 64
;; Assembler: ACME (cross-assembler)
;; Target:    MOS 6502 / Commodore 64
;; Version:   0.2
;; Developer: A. Scarola
;; Date:      February 7, 2026
;;
;; v0.2: LLM behavioral simulation engine
;;   - Scored keyword matching (weighted, topic-aware)
;;   - Response pools (cycling, anti-repetition)
;;   - Template system (word echo from user input)
;;   - Follow-up prompts (clarifying questions)
;;   - Conversation modes (concise/technical/playful)
;;   - Turn milestones (temporal awareness)
;;   - Intent detection (question/statement/followup)
;; ===========================================================

!cpu 6502
!to "c64gpt.prg", cbm

;; =================== HARDWARE ============================

SCREEN      = $0400
COLRAM      = $d800
BORDER      = $d020
BGCOL       = $d021
CHARMODE    = $d018
RASTER      = $d012

CHROUT      = $ffd2
GETIN       = $ffe4
PLOT        = $fff0

;; =================== COLORS ==============================

BLACK       = 0
WHITE       = 1
RED         = 2
CYAN        = 3
PURPLE      = 4
GREEN       = 5
BLUE        = 6
YELLOW      = 7
ORANGE      = 8
BROWN       = 9
LRED        = 10
DGREY       = 11
GREY        = 12
LGREEN      = 13
LBLUE       = 14
LGREY       = 15

;; =================== LAYOUT ==============================

CHAT_TOP    = 2
CHAT_BOT    = 21
INPUT_ROW   = 23

;; =================== BUFFERS =============================

INPUT_BUF   = $c000        ; 80 bytes: raw user input
MATCH_BUF   = $c050        ; 80 bytes: lowercase copy
WORD_BUF    = $c0a0        ; 16 bytes: captured significant word
RESP_BUF    = $c0b0        ; 160 bytes: dynamic response buffer
USER_NAME   = $c150        ; 16 bytes: learned user name
INPUT_MAX   = 76

;; =================== CIA TOD ================================

CIA1_TOD_10TH = $dc08
CIA1_TOD_SEC  = $dc09
CIA1_TOD_MIN  = $dc0a
CIA1_TOD_HRS  = $dc0b
CIA1_CRB      = $dc0f

;; =================== ZERO PAGE ===========================

ptr1        = $fb
ptr1hi      = $fc
ptr2        = $fd
ptr2hi      = $fe

temp        = $02
chat_row    = $03
chat_col    = $04
input_len   = $05
resp_num    = $06
str_idx     = $07
print_col   = $08
delay_flag  = $09

;; v0.2 state
last_topic  = $0a          ; topic of last AI response (0-6)
last_intent = $0b          ; detected user intent (0-4)
best_score  = $0c          ; highest score during keyword scan
conv_mode   = $0d          ; 0=normal 1=concise 2=technical 3=playful
turn_count  = $0e          ; incremented each turn
match_flags = $0f          ; bit7=pool flag during scoring

;; =================== TOPIC IDS ===========================

TOPIC_GREETING   = 0
TOPIC_C64HW      = 1
TOPIC_CODING     = 2
TOPIC_PHILOSOPHY = 3
TOPIC_HUMOR      = 4
TOPIC_META       = 5
TOPIC_GENERAL    = 6

;; =================== INTENT IDS ==========================

INTENT_QUESTION  = 0
INTENT_STATEMENT = 1
INTENT_REQUEST   = 2
INTENT_GREETING  = 3
INTENT_FOLLOWUP  = 4

;; =================== MODE IDS ============================

MODE_NORMAL    = 0
MODE_CONCISE   = 1
MODE_TECHNICAL = 2
MODE_PLAYFUL   = 3

;; ===========================================================
;; BASIC SYS LOADER:  10 SYS 2061
;; ===========================================================

* = $0801

    !byte $0b, $08
    !byte $0a, $00
    !byte $9e
    !pet "2061"
    !byte $00
    !byte $00, $00

;; ===========================================================
;; INITIALIZATION
;; ===========================================================

!zone init
init
    sei
    lda CHARMODE
    ora #$02
    sta CHARMODE

    lda #BLACK
    sta BORDER
    sta BGCOL

    lda #$9b
    jsr CHROUT
    lda #$93
    jsr CHROUT
    cli

    ;; Zero all state vars ($02-$0F)
    lda #0
    sta temp
    sta chat_col
    sta input_len
    sta resp_num
    sta str_idx
    sta print_col
    sta delay_flag
    sta last_topic
    sta last_intent
    sta best_score
    sta conv_mode
    sta turn_count
    sta match_flags

    lda #CHAT_TOP
    sta chat_row

    ;; Clear name state
    lda #0
    sta name_known
    sta input_class

    ;; Clear WORD_BUF
    ldx #15
    lda #0
.clrwb
    sta WORD_BUF,x
    dex
    bpl .clrwb

    ;; Clear USER_NAME
    ldx #15
.clrun
    sta USER_NAME,x
    dex
    bpl .clrun

    jsr draw_title_bar
    jsr draw_separators
    jsr draw_input_prompt

    ;; Welcome message
    lda #LBLUE
    sta print_col
    lda #0
    sta delay_flag
    lda #<msg_welcome
    sta ptr1
    lda #>msg_welcome
    sta ptr1hi
    jsr print_chat

    lda #0
    sta chat_col
    jsr advance_row

;; ===========================================================
;; MAIN LOOP  (v0.2 flow)
;; ===========================================================

!zone main
main_loop
    jsr draw_input_prompt
    jsr get_input

    lda input_len
    beq main_loop

    jsr check_quit
    bcs handle_quit

    ;; Display user message
    jsr display_user_msg

    ;; Pre-process input
    jsr make_lowercase
    jsr capture_word
    jsr detect_intent

    ;; Classify input length
    lda input_len
    cmp #40
    bcs .long_in
    cmp #6
    bcs .med_in
    lda #0
    jmp .store_ic
.long_in
    lda #2
    jmp .store_ic
.med_in
    lda #1
.store_ic
    sta input_class

    ;; Show thinking animation
    jsr show_thinking

    ;; Check mode switch first
    jsr check_mode_switch
    bcs .have_response

    ;; Check followup context
    jsr check_followup_context
    bcs .have_response

    ;; Check conversation stats query
    jsr check_stats_query
    bcs .have_response

    ;; Check date/time commands
    jsr check_datetime
    bcs .have_response

    ;; Check name learning
    jsr check_name_learning
    bcs .have_response

    ;; Scored keyword matching
    jsr score_response
    jsr refine_capture

.have_response
    ;; Display AI response
    jsr display_ai_msg

    ;; Post-response processing
    jsr maybe_followup_prompt
    jsr post_intent_add

    inc turn_count
    jsr check_milestone
    inc resp_num

    jmp main_loop

;; ===========================================================
;; HANDLE QUIT
;; ===========================================================

!zone quit
handle_quit
    lda #CYAN
    sta print_col
    lda #1
    sta delay_flag
    lda #<msg_goodbye
    sta ptr1
    lda #>msg_goodbye
    sta ptr1hi
    jsr print_chat

    jsr long_delay
    jsr long_delay
    jsr long_delay

    lda #$93
    jsr CHROUT
    lda #LBLUE
    sta BORDER
    sta BGCOL
    lda CHARMODE
    and #$fd
    sta CHARMODE
    rts

;; ===========================================================
;; DRAW TITLE BAR
;; ===========================================================

!zone draw_title
draw_title_bar
    clc
    ldx #0
    ldy #0
    jsr PLOT
    lda #$9f
    jsr CHROUT
    lda #$12
    jsr CHROUT
    ldy #0
.loop
    lda txt_title,y
    beq .done
    jsr CHROUT
    iny
    bne .loop
.done
    lda #$92
    jsr CHROUT
    rts

;; ===========================================================
;; DRAW SEPARATORS
;; ===========================================================

!zone draw_seps
draw_separators
    ldy #39
.s1
    lda #$2d
    sta SCREEN + 40, y
    lda #DGREY
    sta COLRAM + 40, y
    dey
    bpl .s1
    ldy #39
.s2
    lda #$2d
    sta SCREEN + 880, y
    lda #DGREY
    sta COLRAM + 880, y
    dey
    bpl .s2
    rts

;; ===========================================================
;; DRAW INPUT PROMPT
;; ===========================================================

!zone draw_prompt
draw_input_prompt
    ldx #INPUT_ROW
    lda row_lo,x
    sta ptr2
    lda row_hi,x
    sta ptr2hi
    ;; Clear 80 chars (rows 23 and 24, contiguous)
    ldy #79
    lda #$20
.clr
    sta (ptr2),y
    dey
    bpl .clr

    ;; Color 80 chars
    lda ptr2hi
    clc
    adc #$d4
    sta ptr2hi
    ldy #79
    lda #LGREEN
.col
    sta (ptr2),y
    dey
    bpl .col

    clc
    ldx #INPUT_ROW
    ldy #0
    jsr PLOT
    lda #$99
    jsr CHROUT
    lda #$3e
    jsr CHROUT
    lda #$20
    jsr CHROUT
    rts

;; ===========================================================
;; GET USER INPUT
;; ===========================================================

!zone get_input
get_input
    lda #0
    sta input_len
    clc
    ldx #INPUT_ROW
    ldy #2
    jsr PLOT
    lda #$99
    jsr CHROUT

.key_wait
    jsr GETIN
    beq .key_wait
    cmp #$0d
    beq .done
    cmp #$14
    beq .bksp
    cmp #$20
    bcc .key_wait
    ldx input_len
    cpx #INPUT_MAX
    bcs .key_wait
    sta INPUT_BUF,x
    inc input_len
    jsr CHROUT
    jmp .key_wait

.bksp
    ldx input_len
    beq .key_wait
    dec input_len
    lda #$9d
    jsr CHROUT
    lda #$20
    jsr CHROUT
    lda #$9d
    jsr CHROUT
    jmp .key_wait

.done
    ldx input_len
    lda #0
    sta INPUT_BUF,x
    rts

;; ===========================================================
;; CHECK QUIT
;; ===========================================================

!zone check_quit
check_quit
    jsr make_lowercase

    lda #<kw_quit
    sta ptr2
    lda #>kw_quit
    sta ptr2hi
    jsr substr_search
    bcs .yes

    lda #<kw_exit
    sta ptr2
    lda #>kw_exit
    sta ptr2hi
    jsr substr_search
    bcs .yes

    lda #<kw_bye
    sta ptr2
    lda #>kw_bye
    sta ptr2hi
    jsr substr_search
    rts
.yes
    sec
    rts

;; ===========================================================
;; DISPLAY USER MESSAGE
;; ===========================================================

!zone disp_user
display_user_msg
    lda #LGREEN
    sta print_col
    lda #0
    sta delay_flag
    lda #<lbl_you
    sta ptr1
    lda #>lbl_you
    sta ptr1hi
    jsr print_chat

    lda #LGREY
    sta print_col
    lda #<INPUT_BUF
    sta ptr1
    lda #>INPUT_BUF
    sta ptr1hi
    jsr print_chat

    lda #0
    sta chat_col
    jsr advance_row
    rts

;; ===========================================================
;; SHOW THINKING ANIMATION
;; ===========================================================

!zone thinking
show_thinking
    lda chat_row
    sta think_row

    lda #CYAN
    sta print_col
    lda #0
    sta delay_flag
    lda #<lbl_ai
    sta ptr1
    lda #>lbl_ai
    sta ptr1hi
    jsr print_chat

    lda #DGREY
    sta print_col
    lda #<txt_thinking
    sta ptr1
    lda #>txt_thinking
    sta ptr1hi
    jsr print_chat

    ldx #3
.dot_lp
    stx temp
    clc
    ldx chat_row
    ldy chat_col
    jsr PLOT
    lda #$97
    jsr CHROUT
    lda #$2e
    jsr CHROUT
    inc chat_col
    jsr medium_delay
    ldx temp
    dex
    bne .dot_lp

    jsr long_delay

    ldx think_row
    lda row_lo,x
    sta ptr2
    lda row_hi,x
    sta ptr2hi
    ldy #39
    lda #$20
.clr
    sta (ptr2),y
    dey
    bpl .clr

    lda think_row
    sta chat_row
    lda #0
    sta chat_col
    rts

think_row  !byte 0

;; ===========================================================
;; DISPLAY AI MESSAGE
;; ===========================================================

!zone disp_ai
display_ai_msg
    lda #CYAN
    sta print_col
    lda #0
    sta delay_flag
    lda #<lbl_ai
    sta ptr1
    lda #>lbl_ai
    sta ptr1hi
    jsr print_chat

    lda #LGREY
    sta print_col
    lda #1
    sta delay_flag
    lda resp_ptr
    sta ptr1
    lda resp_ptr+1
    sta ptr1hi
    jsr print_chat

    lda #0
    sta chat_col
    jsr advance_row
    rts

;; ===========================================================
;; PRINT CHAT STRING
;; v0.2: handles $01 template marker (inserts WORD_BUF)
;;        and $02 template marker (inserts USER_NAME)
;; ===========================================================

!zone print_chat
print_chat
    lda #0
    sta str_idx

    ldx print_col
    lda petscii_colors,x
    jsr CHROUT

    clc
    ldx chat_row
    ldy chat_col
    jsr PLOT

.loop
    ldy str_idx
    lda (ptr1),y
    beq .done

    cmp #$01
    beq .tmpl_insert

    cmp #$02
    beq .tmpl_name

    cmp #$0d
    beq .newline

    jsr CHROUT

    inc chat_col
    lda chat_col
    cmp #40
    bcc .no_wrap

    lda #0
    sta chat_col
    jsr advance_row
    clc
    ldx chat_row
    ldy #0
    jsr PLOT

.no_wrap
    lda delay_flag
    beq .skip_delay
    jsr type_delay
.skip_delay
    inc str_idx
    jmp .loop

.newline
    lda #0
    sta chat_col
    jsr advance_row
    clc
    ldx chat_row
    ldy #0
    jsr PLOT
    inc str_idx
    jmp .loop

.tmpl_insert
    jsr insert_word
    inc str_idx
    jmp .loop

.tmpl_name
    jsr insert_name
    inc str_idx
    jmp .loop

.done
    rts

;; ===========================================================
;; INSERT NAME  (prints USER_NAME inline during template)
;; If name not known, prints "friend" instead.
;; ===========================================================

!zone insert_name
insert_name
    lda name_known
    bne .has_name
    ;; Print "friend" as fallback
    ldy #0
.fb_loop
    lda in_friend,y
    beq .fb_done
    sty iw_save
    jsr CHROUT
    inc chat_col
    lda chat_col
    cmp #40
    bcc .fb_nw
    lda #0
    sta chat_col
    jsr advance_row
    clc
    ldx chat_row
    ldy #0
    jsr PLOT
.fb_nw
    lda delay_flag
    beq .fb_nd
    jsr type_delay
.fb_nd
    ldy iw_save
    iny
    bne .fb_loop
.fb_done
    rts

.has_name
    ldy #0
.nm_loop
    lda USER_NAME,y
    beq .nm_done
    sty iw_save
    jsr CHROUT
    inc chat_col
    lda chat_col
    cmp #40
    bcc .nm_nw
    lda #0
    sta chat_col
    jsr advance_row
    clc
    ldx chat_row
    ldy #0
    jsr PLOT
.nm_nw
    lda delay_flag
    beq .nm_nd
    jsr type_delay
.nm_nd
    ldy iw_save
    iny
    bne .nm_loop
.nm_done
    rts

in_friend  !pet "friend", 0

;; ===========================================================
;; INSERT WORD  (prints WORD_BUF inline during template)
;; ===========================================================

!zone insert_word
insert_word
    ldy #0
.loop
    lda WORD_BUF,y
    beq .done
    sty iw_save
    jsr CHROUT
    inc chat_col
    lda chat_col
    cmp #40
    bcc .no_wrap
    lda #0
    sta chat_col
    jsr advance_row
    clc
    ldx chat_row
    ldy #0
    jsr PLOT
.no_wrap
    lda delay_flag
    beq .no_delay
    jsr type_delay
.no_delay
    ldy iw_save
    iny
    bne .loop
.done
    rts
iw_save !byte 0

;; ===========================================================
;; ADVANCE CHAT ROW
;; ===========================================================

!zone advance
advance_row
    inc chat_row
    lda chat_row
    cmp #CHAT_BOT+1
    bcc .ok
    jsr scroll_chat
    lda #CHAT_BOT
    sta chat_row
.ok
    rts

;; ===========================================================
;; SCROLL CHAT AREA
;; ===========================================================

!zone scroll
scroll_chat
    lda ptr1
    pha
    lda ptr1hi
    pha
    lda ptr2
    pha
    lda ptr2hi
    pha

    ldx #CHAT_TOP
.row_loop
    stx temp
    inx
    lda row_lo,x
    sta ptr1
    lda row_hi,x
    sta ptr1hi
    ldx temp
    lda row_lo,x
    sta ptr2
    lda row_hi,x
    sta ptr2hi

    ldy #39
.cscr
    lda (ptr1),y
    sta (ptr2),y
    dey
    bpl .cscr

    lda ptr1hi
    clc
    adc #$d4
    sta ptr1hi
    lda ptr2hi
    clc
    adc #$d4
    sta ptr2hi

    ldy #39
.ccol
    lda (ptr1),y
    sta (ptr2),y
    dey
    bpl .ccol

    ldx temp
    inx
    cpx #CHAT_BOT
    bcs .scroll_done
    jmp .row_loop

.scroll_done
    ldx #CHAT_BOT
    lda row_lo,x
    sta ptr1
    lda row_hi,x
    sta ptr1hi
    ldy #39
    lda #$20
.clrscr
    sta (ptr1),y
    dey
    bpl .clrscr

    lda ptr1hi
    clc
    adc #$d4
    sta ptr1hi
    ldy #39
    lda #LGREY
.clrcol
    sta (ptr1),y
    dey
    bpl .clrcol

    pla
    sta ptr2hi
    pla
    sta ptr2
    pla
    sta ptr1hi
    pla
    sta ptr1
    rts

;; ===========================================================
;; MAKE LOWERCASE  (INPUT_BUF -> MATCH_BUF)
;; ===========================================================

!zone lowercase
make_lowercase
    ldx #0
.loop
    lda INPUT_BUF,x
    beq .done
    cmp #$c1
    bcc .store
    cmp #$db
    bcs .store
    sec
    sbc #$80
.store
    sta MATCH_BUF,x
    inx
    cpx #80
    bcc .loop
.done
    lda #0
    sta MATCH_BUF,x
    rts

;; ===========================================================
;; CAPTURE WORD
;; Extracts first significant word (>=4 chars, not in skip
;; list) from MATCH_BUF into WORD_BUF. Falls back to "that".
;; ===========================================================

!zone capture_word
capture_word
    ldx #0

.next_word
    lda MATCH_BUF,x
    beq .use_fallback
    cmp #$20
    beq .skip_delim
    cmp #$3f            ; '?'
    beq .skip_delim
    cmp #$21            ; '!'
    beq .skip_delim
    cmp #$2e            ; '.'
    beq .skip_delim
    cmp #$2c            ; ','
    beq .skip_delim
    bne .found_start
.skip_delim
    inx
    jmp .next_word

.found_start
    stx temp            ; save word start
    ldy #0
.measure
    lda MATCH_BUF,x
    beq .check_len
    cmp #$20
    beq .check_len
    cmp #$3f            ; '?'
    beq .check_len
    cmp #$21            ; '!'
    beq .check_len
    cmp #$2e            ; '.'
    beq .check_len
    cmp #$2c            ; ','
    beq .check_len
    inx
    iny
    jmp .measure

.check_len
    ;; Y = word length, X = past end of word
    cpy #4
    bcc .next_word      ; too short, skip

    ;; Save X (end position) for later
    txa
    pha

    jsr check_skip_word

    pla
    tax

    bcs .next_word      ; in skip list, skip

    ;; Good word - copy to WORD_BUF
    ldx temp
    ldy #0
.copy
    lda MATCH_BUF,x
    beq .cap_done
    cmp #$20
    beq .cap_done
    cmp #$3f            ; '?'
    beq .cap_done
    cmp #$21            ; '!'
    beq .cap_done
    cmp #$2e            ; '.'
    beq .cap_done
    cmp #$2c            ; ','
    beq .cap_done
    cpy #15
    bcs .cap_done
    sta WORD_BUF,y
    inx
    iny
    jmp .copy

.cap_done
    lda #0
    sta WORD_BUF,y
    rts

.use_fallback
    ldx #0
.fb_cp
    lda fallback_word,x
    sta WORD_BUF,x
    beq .fb_done
    inx
    bne .fb_cp
.fb_done
    rts

;; ===========================================================
;; CHECK SKIP WORD
;; Tests word at MATCH_BUF+temp against skip list.
;; Returns C=1 if word should be skipped.
;; ===========================================================

!zone check_skip
check_skip_word
    lda #<skip_list
    sta ptr2
    lda #>skip_list
    sta ptr2hi

.check_next
    ldy #0
    lda (ptr2),y
    beq .not_found          ; end of skip list

    ldx temp
    ldy #0
.cmp_loop
    lda (ptr2),y
    beq .check_end          ; end of skip word
    cmp MATCH_BUF,x
    bne .skip_this
    inx
    iny
    jmp .cmp_loop

.check_end
    ;; Skip word matched fully. Input word must also end here.
    lda MATCH_BUF,x
    beq .found
    cmp #$20
    beq .found
    ;; Not a full word match, skip word is prefix

.skip_this
    ;; Advance ptr2 past this skip word's null terminator
    ldy #0
.adv
    lda (ptr2),y
    beq .adv_done
    iny
    jmp .adv
.adv_done
    iny                     ; skip the null byte
    tya
    clc
    adc ptr2
    sta ptr2
    bcc .check_next
    inc ptr2hi
    jmp .check_next

.found
    sec
    rts
.not_found
    clc
    rts

;; ===========================================================
;; REFINE CAPTURE
;; If a keyword matched, overwrite WORD_BUF with the word
;; immediately after the keyword in MATCH_BUF.
;; ===========================================================

!zone refine_capture
refine_capture
    lda best_score
    beq .rc_done            ; no keyword match, keep original

    ldx best_match_end
    ;; Skip spaces after keyword
.rc_skip
    lda MATCH_BUF,x
    beq .rc_done            ; end of input, keep original
    cmp #$20
    bne .rc_start
    inx
    jmp .rc_skip

.rc_start
    ;; Found a word, measure length
    stx temp
    ldy #0
.rc_measure
    lda MATCH_BUF,x
    beq .rc_check
    cmp #$20
    beq .rc_check
    cmp #$3f            ; '?'
    beq .rc_check
    cmp #$21            ; '!'
    beq .rc_check
    cmp #$2e            ; '.'
    beq .rc_check
    cmp #$2c            ; ','
    beq .rc_check
    inx
    iny
    jmp .rc_measure

.rc_check
    cpy #3
    bcc .rc_done            ; too short, keep original

    ;; Good word, copy to WORD_BUF
    ldx temp
    ldy #0
.rc_copy
    lda MATCH_BUF,x
    beq .rc_end
    cmp #$20
    beq .rc_end
    cmp #$3f            ; '?'
    beq .rc_end
    cmp #$21            ; '!'
    beq .rc_end
    cmp #$2e            ; '.'
    beq .rc_end
    cmp #$2c            ; ','
    beq .rc_end
    cpy #15
    bcs .rc_end
    sta WORD_BUF,y
    inx
    iny
    jmp .rc_copy
.rc_end
    lda #0
    sta WORD_BUF,y
.rc_done
    rts

;; ===========================================================
;; DETECT INTENT
;; Sets last_intent based on input analysis.
;; ===========================================================

!zone detect_intent
detect_intent
    ;; 1) Check for '?' in input
    ldx #0
.scan
    lda MATCH_BUF,x
    beq .no_q
    cmp #$3f
    beq .question
    inx
    bne .scan

.no_q
    ;; 2) Short input + followup context? Keep followup.
    lda input_len
    cmp #6
    bcs .check_words
    lda last_intent
    cmp #INTENT_FOLLOWUP
    beq .done               ; keep FOLLOWUP intent

.check_words
    ;; 3) Check question words
    lda #<iw_tbl_q
    sta ptr2
    lda #>iw_tbl_q
    sta ptr2hi
    jsr check_first_word
    bcs .question

    ;; 4) Check greeting words
    lda #<iw_tbl_g
    sta ptr2
    lda #>iw_tbl_g
    sta ptr2hi
    jsr check_first_word
    bcs .greeting

    ;; 5) Check request words
    lda #<iw_tbl_r
    sta ptr2
    lda #>iw_tbl_r
    sta ptr2hi
    jsr check_first_word
    bcs .request

    ;; 6) Default to statement
    lda #INTENT_STATEMENT
    sta last_intent
.done
    rts

.question
    lda #INTENT_QUESTION
    sta last_intent
    rts

.greeting
    lda #INTENT_GREETING
    sta last_intent
    rts

.request
    lda #INTENT_REQUEST
    sta last_intent
    rts

;; ===========================================================
;; CHECK FIRST WORD
;; Compares first word of MATCH_BUF against null-separated
;; word list at ptr2 (double-null terminated).
;; Returns C=1 if match, C=0 if not.
;; ===========================================================

!zone check_first_word
check_first_word
    ;; Find length of first word in MATCH_BUF
    ldx #0
.fw_skip
    lda MATCH_BUF,x
    beq .fw_nomatch         ; empty input
    cmp #$20
    bne .fw_got
    inx
    jmp .fw_skip
.fw_got
    ;; X = start of first word in MATCH_BUF
    stx cfw_start

.fw_next_entry
    ;; Check if we've hit double-null (end of list)
    ldy #0
    lda (ptr2),y
    beq .fw_nomatch

    ;; Compare this entry against first word
    ldx cfw_start
    ldy #0
.fw_cmp
    lda (ptr2),y
    beq .fw_entry_end       ; end of list word
    cmp MATCH_BUF,x
    bne .fw_advance
    inx
    iny
    jmp .fw_cmp

.fw_entry_end
    ;; List word ended. Input word must also end here.
    lda MATCH_BUF,x
    beq .fw_match
    cmp #$20
    beq .fw_match
    ;; Input word is longer, not a match

.fw_advance
    ;; Skip past this entry's null terminator
    ldy #0
.fw_adv
    lda (ptr2),y
    beq .fw_adv_done
    iny
    jmp .fw_adv
.fw_adv_done
    iny                     ; skip the null byte
    tya
    clc
    adc ptr2
    sta ptr2
    bcc .fw_next_entry
    inc ptr2hi
    jmp .fw_next_entry

.fw_nomatch
    clc
    rts
.fw_match
    sec
    rts

cfw_start !byte 0

;; ===========================================================
;; CHECK MODE SWITCH
;; Detects "be brief", "be funny", etc. Sets conv_mode.
;; Returns C=1 if mode changed (resp_ptr set), C=0 if not.
;; ===========================================================

!zone check_mode
check_mode_switch
    lda #<kw_be_brief
    sta ptr2
    lda #>kw_be_brief
    sta ptr2hi
    jsr substr_search
    bcs .set_concise

    lda #<kw_be_concise
    sta ptr2
    lda #>kw_be_concise
    sta ptr2hi
    jsr substr_search
    bcs .set_concise

    lda #<kw_be_technical
    sta ptr2
    lda #>kw_be_technical
    sta ptr2hi
    jsr substr_search
    bcs .set_technical

    lda #<kw_be_detailed
    sta ptr2
    lda #>kw_be_detailed
    sta ptr2hi
    jsr substr_search
    bcs .set_technical

    lda #<kw_be_funny
    sta ptr2
    lda #>kw_be_funny
    sta ptr2hi
    jsr substr_search
    bcs .set_playful

    lda #<kw_be_playful
    sta ptr2
    lda #>kw_be_playful
    sta ptr2hi
    jsr substr_search
    bcs .set_playful

    lda #<kw_be_normal
    sta ptr2
    lda #>kw_be_normal
    sta ptr2hi
    jsr substr_search
    bcs .set_normal

    clc
    rts

.set_concise
    lda #MODE_CONCISE
    sta conv_mode
    lda #<resp_mode_concise
    sta resp_ptr
    lda #>resp_mode_concise
    sta resp_ptr+1
    sec
    rts

.set_technical
    lda #MODE_TECHNICAL
    sta conv_mode
    lda #<resp_mode_tech
    sta resp_ptr
    lda #>resp_mode_tech
    sta resp_ptr+1
    sec
    rts

.set_playful
    lda #MODE_PLAYFUL
    sta conv_mode
    lda #<resp_mode_playful
    sta resp_ptr
    lda #>resp_mode_playful
    sta resp_ptr+1
    sec
    rts

.set_normal
    lda #MODE_NORMAL
    sta conv_mode
    lda #<resp_mode_normal
    sta resp_ptr
    lda #>resp_mode_normal
    sta resp_ptr+1
    sec
    rts

;; ===========================================================
;; CHECK FOLLOWUP CONTEXT
;; Handles "tell me more" / depth requests (any time),
;; and yes/no/ok followups (when last_intent==FOLLOWUP).
;; Returns C=1 if handled (resp_ptr set), C=0 if not.
;; ===========================================================

!zone check_fu
check_followup_context
    ;; --- "Tell me more" / depth checks (always active) ---
    lda #<kw_dp_more
    sta ptr2
    lda #>kw_dp_more
    sta ptr2hi
    jsr substr_search
    bcs .do_depth

    lda #<kw_dp_more2
    sta ptr2
    lda #>kw_dp_more2
    sta ptr2hi
    jsr substr_search
    bcs .do_depth

    lda #<kw_dp_goon
    sta ptr2
    lda #>kw_dp_goon
    sta ptr2hi
    jsr substr_search
    bcs .do_depth

    lda #<kw_dp_elab
    sta ptr2
    lda #>kw_dp_elab
    sta ptr2hi
    jsr substr_search
    bcs .do_depth

    jmp .check_std_fu

.do_depth
    ;; Look up last_topic in deeper_tbl
    lda last_topic
    asl                     ; *2 for word index
    tax
    lda deeper_tbl,x
    sta resp_ptr
    lda deeper_tbl+1,x
    sta resp_ptr+1
    lda #INTENT_STATEMENT
    sta last_intent
    sec
    rts

.check_std_fu
    ;; --- Standard followup context ---
    lda last_intent
    cmp #INTENT_FOLLOWUP
    bne .no_fu

    lda input_len
    cmp #6
    bcs .no_fu

    lda #<kw_fu_yes
    sta ptr2
    lda #>kw_fu_yes
    sta ptr2hi
    jsr substr_search
    bcs .cont_yes

    lda #<kw_fu_sure
    sta ptr2
    lda #>kw_fu_sure
    sta ptr2hi
    jsr substr_search
    bcs .cont_yes

    lda #<kw_fu_ok
    sta ptr2
    lda #>kw_fu_ok
    sta ptr2hi
    jsr substr_search
    bcs .cont_yes

    lda #<kw_fu_no
    sta ptr2
    lda #>kw_fu_no
    sta ptr2hi
    jsr substr_search
    bcs .cont_no

.no_fu
    lda #INTENT_STATEMENT
    sta last_intent
    clc
    rts

.cont_yes
    lda #<resp_cont_yes
    sta resp_ptr
    lda #>resp_cont_yes
    sta resp_ptr+1
    lda #INTENT_STATEMENT
    sta last_intent
    sec
    rts

.cont_no
    lda #<resp_cont_no
    sta resp_ptr
    lda #>resp_cont_no
    sta resp_ptr+1
    lda #INTENT_STATEMENT
    sta last_intent
    sec
    rts

;; ===========================================================
;; SUBSTRING SEARCH
;; Searches for null-terminated keyword at ptr2 in MATCH_BUF.
;; Returns C=1 found, C=0 not found.
;; ===========================================================

!zone substr
substr_search
    ldx #0
.outer
    lda MATCH_BUF,x
    beq .notfound
    stx temp
    ldy #0
.inner
    lda (ptr2),y
    beq .found
    cmp MATCH_BUF,x
    bne .next_pos
    inx
    iny
    jmp .inner
.next_pos
    ldx temp
    inx
    jmp .outer
.notfound
    clc
    rts
.found
    sec
    rts

;; ===========================================================
;; SCORE RESPONSE  (v0.2 weighted keyword matching engine)
;; Scans ALL keywords, picks highest-scoring match.
;; Table format: keyword_ptr(2), resp_ptr(2), weight_flags(1), topic(1)
;; ===========================================================

!zone score_resp
score_response
    lda #0
    sta best_score
    sta best_resp
    sta best_resp+1

    lda #<keyword_tbl
    sta ptr1
    lda #>keyword_tbl
    sta ptr1hi

.scan_loop
    ;; Read keyword pointer
    ldy #0
    lda (ptr1),y
    sta ptr2
    iny
    lda (ptr1),y
    sta ptr2hi

    ;; End of table?
    ora ptr2
    bne .have_kw
    jmp .scan_done
.have_kw

    ;; Save table pointer
    lda ptr1
    pha
    lda ptr1hi
    pha

    jsr substr_search
    stx match_end_tmp

    pla
    sta ptr1hi
    pla
    sta ptr1

    bcc .advance

    ;; === MATCH: check for negation ===
    jsr check_negation
    bcs .advance            ; negated — skip this keyword

    ;; === MATCH: calculate score ===

    ;; Base weight (bits 0-6 of weight_flags byte)
    ldy #4
    lda (ptr1),y
    and #$7f
    sta temp                ; temp = score

    ;; Topic continuity bonus
    ldy #5
    lda (ptr1),y
    cmp last_topic
    bne .no_topic_bonus
    inc temp
.no_topic_bonus

    ;; Mode bonus
    lda conv_mode
    beq .no_mode_bonus      ; MODE_NORMAL, no bonus
    cmp #MODE_PLAYFUL
    bne .check_tech_mode
    ldy #5
    lda (ptr1),y
    cmp #TOPIC_HUMOR
    bne .no_mode_bonus
    inc temp
    jmp .no_mode_bonus

.check_tech_mode
    lda conv_mode
    cmp #MODE_TECHNICAL
    bne .no_mode_bonus
    ldy #5
    lda (ptr1),y
    cmp #TOPIC_CODING
    beq .give_mode_bonus
    cmp #TOPIC_C64HW
    bne .no_mode_bonus
.give_mode_bonus
    inc temp

.no_mode_bonus
    ;; Compare with best score
    lda temp
    cmp best_score
    bcc .advance            ; less than best, skip

    ;; New best (or tie): update
    sta best_score

    ldy #2
    lda (ptr1),y
    sta best_resp
    iny
    lda (ptr1),y
    sta best_resp+1

    ldy #4
    lda (ptr1),y
    sta match_flags

    ldy #5
    lda (ptr1),y
    sta best_topic

    lda match_end_tmp
    sta best_match_end

.advance
    lda ptr1
    clc
    adc #6
    sta ptr1
    bcc +
    inc ptr1hi
+   jmp .scan_loop

.scan_done
    lda best_score
    beq .fallback

    ;; Update conversation state
    lda best_topic
    sta last_topic

    ;; Check pool flag (bit 7)
    lda match_flags
    bmi .is_pool

    ;; Direct response
    lda best_resp
    sta resp_ptr
    lda best_resp+1
    sta resp_ptr+1
    rts

.is_pool
    jsr resolve_pool
    rts

.fallback
    jsr get_generic
    rts

best_resp      !word 0
best_topic     !byte 0
match_end_tmp  !byte 0
best_match_end !byte 0

;; ===========================================================
;; RESOLVE POOL
;; Reads from pool at best_resp, sets resp_ptr.
;; Pool format: count(1), idx(1), ptr0(2), ptr1(2), ...
;; Mode influences selection.
;; ===========================================================

!zone resolve_pool
resolve_pool
    lda best_resp
    sta ptr1
    lda best_resp+1
    sta ptr1hi

    ;; Check mode overrides
    lda conv_mode
    cmp #MODE_CONCISE
    beq .force_first
    cmp #MODE_PLAYFUL
    beq .force_last

    ;; Normal: use cycling index
    ldy #1
    lda (ptr1),y
    jmp .use_idx

.force_first
    lda #0
    jmp .use_idx

.force_last
    ldy #0
    lda (ptr1),y        ; count
    sec
    sbc #1              ; last index

.use_idx
    ;; A = index to use
    asl                 ; *2 for word offset
    clc
    adc #2              ; skip count+idx header
    tay

    ;; Read response pointer
    lda (ptr1),y
    sta resp_ptr
    iny
    lda (ptr1),y
    sta resp_ptr+1

    ;; Advance cycling index (skip if mode-forced)
    lda conv_mode
    cmp #MODE_CONCISE
    beq .done
    cmp #MODE_PLAYFUL
    beq .done

    ldy #1
    lda (ptr1),y        ; current idx
    clc
    adc #1
    ldy #0
    cmp (ptr1),y        ; >= count?
    bcc .no_wrap
    lda #0
.no_wrap
    ldy #1
    sta (ptr1),y        ; store new idx

.done
    ;; Check if this is hello_pool — add time greeting
    lda best_resp
    cmp #<hello_pool
    bne .no_tg
    lda best_resp+1
    cmp #>hello_pool
    bne .no_tg
    jsr check_time_greeting
    ;; If C=1, RESP_BUF has time greeting; resp_ptr already set
.no_tg
    rts

;; ===========================================================
;; GET GENERIC (fallback with template support)
;; ===========================================================

!zone generic
get_generic
    ;; If long input, build prefixed response in RESP_BUF
    lda input_class
    cmp #2
    bne .normal_gen

    ;; Long input: prefix with thoughtful acknowledgment
    jsr buf_init
    lda #<str_thoughtful
    sta ptr2
    lda #>str_thoughtful
    sta ptr2hi
    jsr buf_append_str

    ;; Pick a generic and append it
    jsr .pick_generic
    lda resp_ptr
    sta ptr2
    lda resp_ptr+1
    sta ptr2hi
    jsr buf_append_str

    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

.normal_gen
    jsr .pick_generic
    rts

.pick_generic
    lda RASTER
    lsr
    lsr
    lsr
    eor resp_num
    and #$0f            ; 0..15 for 16 generics
    cmp #NUM_GENERIC
    bcc .ok
    sec
    sbc #NUM_GENERIC
    cmp #NUM_GENERIC
    bcc .ok
    lda #0
.ok
    asl
    tax
    lda generic_tbl,x
    sta resp_ptr
    lda generic_tbl+1,x
    sta resp_ptr+1
    rts

resp_ptr   !word 0

;; ===========================================================
;; MAYBE FOLLOWUP PROMPT
;; Checks if current response has a follow-up question.
;; If so, prints it in yellow and sets INTENT_FOLLOWUP.
;; ===========================================================

!zone maybe_fu
maybe_followup_prompt
    lda #<followup_tbl
    sta ptr2
    lda #>followup_tbl
    sta ptr2hi

.check
    ldy #0
    lda (ptr2),y
    sta temp
    iny
    lda (ptr2),y

    ;; End of table?
    ora temp
    beq .no_fu

    ;; Compare with resp_ptr
    ldy #0
    lda (ptr2),y
    cmp resp_ptr
    bne .next_entry
    iny
    lda (ptr2),y
    cmp resp_ptr+1
    bne .next_entry

    ;; Match! Get followup string pointer
    ldy #2
    lda (ptr2),y
    pha
    iny
    lda (ptr2),y
    sta ptr1hi
    pla
    sta ptr1

    ;; Print followup in yellow
    lda #0
    sta chat_col
    jsr advance_row
    lda #YELLOW
    sta print_col
    lda #1
    sta delay_flag
    jsr print_chat

    lda #INTENT_FOLLOWUP
    sta last_intent
    rts

.next_entry
    lda ptr2
    clc
    adc #4
    sta ptr2
    bcc .check
    inc ptr2hi
    jmp .check

.no_fu
    rts

;; ===========================================================
;; CHECK MILESTONE
;; Prints a bonus remark at turn 5, 10, 20.
;; ===========================================================

!zone milestone
check_milestone
    lda turn_count
    cmp #5
    beq .m5
    cmp #10
    beq .m10
    cmp #20
    beq .m20
    rts

.m5
    lda #<milestone_5
    sta ptr1
    lda #>milestone_5
    sta ptr1hi
    jmp .print_it
.m10
    lda #<milestone_10
    sta ptr1
    lda #>milestone_10
    sta ptr1hi
    jmp .print_it
.m20
    lda #<milestone_20
    sta ptr1
    lda #>milestone_20
    sta ptr1hi
.print_it
    lda #0
    sta chat_col
    jsr advance_row
    lda #DGREY
    sta print_col
    lda #0
    sta delay_flag
    jsr print_chat
    lda #0
    sta chat_col
    jsr advance_row
    rts

;; ===========================================================
;; POST INTENT ADD
;; After question/request intent, occasionally append a
;; brief conversational aside like "Does that help?"
;; ===========================================================

!zone post_intent
post_intent_add
    ;; Only for QUESTION or REQUEST intents
    lda last_intent
    cmp #INTENT_QUESTION
    beq .pia_check
    cmp #INTENT_REQUEST
    beq .pia_check
    rts

.pia_check
    ;; Only trigger every 3rd applicable turn (mod 3 == 0)
    ;; Also skip turn 0 so first question isn't cluttered
    lda turn_count
    beq .pia_skip
    ;; Mod 3: subtract 3 until < 3
.pia_mod3
    cmp #3
    bcc .pia_test
    sec
    sbc #3
    jmp .pia_mod3
.pia_test
    cmp #0
    bne .pia_skip

    ;; Pick from 3 strings using turn_count / 3 mod 3
    lda turn_count
    lsr                     ; approximate: turn/2 gives variety
    ;; Mod 3 again for index
.pia_mod3b
    cmp #3
    bcc .pia_pick
    sec
    sbc #3
    jmp .pia_mod3b
.pia_pick
    asl
    tax
    lda iq_tbl,x
    sta ptr1
    lda iq_tbl+1,x
    sta ptr1hi

    ;; Print in DGREY, no typewriter
    lda #0
    sta chat_col
    jsr advance_row
    lda #DGREY
    sta print_col
    lda #0
    sta delay_flag
    jsr print_chat
    lda #0
    sta chat_col
    jsr advance_row

.pia_skip
    rts

;; ===========================================================
;; CHECK DATE/TIME COMMANDS
;; Dispatches to set/read date or time handlers.
;; Returns C=1 if handled (resp_ptr set), C=0 if not.
;; ===========================================================

!zone check_datetime
check_datetime
    ;; Check if both "date" and "time" mentioned → show both
    lda #<kw_dt_dateword
    sta ptr2
    lda #>kw_dt_dateword
    sta ptr2hi
    jsr substr_search
    bcc .dt_not_both

    lda #<kw_dt_timeword
    sta ptr2
    lda #>kw_dt_timeword
    sta ptr2hi
    jsr substr_search
    bcc .dt_not_both

    ;; Both present. If no month name and no colon → read both.
    jsr find_month
    bcs .dt_not_both        ; month found → set logic below

    ldx #0
.dt_both_colon
    lda MATCH_BUF,x
    beq .dt_read_both       ; no colon → read both
    cmp #$3a
    beq .dt_not_both        ; colon found → set logic below
    inx
    jmp .dt_both_colon

.dt_read_both
    jsr format_both_resp
    sec
    rts

.dt_not_both
    ;; "today" → date command
    lda #<kw_dt_today
    sta ptr2
    lda #>kw_dt_today
    sta ptr2hi
    jsr substr_search
    bcs .dt_date_cmd

    ;; "the date" → date command
    lda #<kw_dt_thedate
    sta ptr2
    lda #>kw_dt_thedate
    sta ptr2hi
    jsr substr_search
    bcs .dt_date_cmd

    ;; "what day" → date read
    lda #<kw_dt_whatday
    sta ptr2
    lda #>kw_dt_whatday
    sta ptr2hi
    jsr substr_search
    bcs .dt_read_date

    ;; "what time" → time read
    lda #<kw_dt_whattime
    sta ptr2
    lda #>kw_dt_whattime
    sta ptr2hi
    jsr substr_search
    bcs .dt_read_time

    ;; "the time" → time command
    lda #<kw_dt_thetime
    sta ptr2
    lda #>kw_dt_thetime
    sta ptr2hi
    jsr substr_search
    bcs .dt_time_cmd

    ;; "time is" → time command
    lda #<kw_dt_timeis
    sta ptr2
    lda #>kw_dt_timeis
    sta ptr2hi
    jsr substr_search
    bcs .dt_time_cmd

    clc
    rts

.dt_date_cmd
    ;; Month name present? → set. Otherwise → read.
    jsr find_month
    bcc .dt_read_date
    ;; A = month number, X = pos after match
    jsr do_set_date
    sec
    rts

.dt_read_date
    jsr format_date_resp
    sec
    rts

.dt_time_cmd
    ;; Colon present? → set. Otherwise → read.
    ldx #0
.dt_colon_scan
    lda MATCH_BUF,x
    beq .dt_read_time
    cmp #$3a            ; ':'
    beq .dt_do_set_time
    inx
    jmp .dt_colon_scan

.dt_do_set_time
    jsr do_set_time
    sec
    rts

.dt_read_time
    jsr format_time_resp
    sec
    rts

;; ===========================================================
;; FIND MONTH
;; Scans MATCH_BUF for a 3-letter month abbreviation.
;; Returns C=1 if found: A=month (1-12), X=pos after match.
;; Returns C=0 if not found.
;; ===========================================================

!zone find_month
find_month
    lda #<month_abbrevs
    sta ptr1
    lda #>month_abbrevs
    sta ptr1hi
    lda #1
    sta fm_month

.fm_loop
    ldy #0
    lda (ptr1),y
    beq .fm_notfound        ; double-null = end of table

    ;; Set ptr2 = current month abbreviation
    lda ptr1
    sta ptr2
    lda ptr1hi
    sta ptr2hi

    ;; Save ptr1
    lda ptr1
    pha
    lda ptr1hi
    pha

    jsr substr_search

    pla
    sta ptr1hi
    pla
    sta ptr1

    bcs .fm_found

    ;; Advance ptr1 past this entry's null
    ldy #0
.fm_adv
    lda (ptr1),y
    beq .fm_adv_done
    iny
    jmp .fm_adv
.fm_adv_done
    iny
    tya
    clc
    adc ptr1
    sta ptr1
    bcc +
    inc ptr1hi
+
    inc fm_month
    jmp .fm_loop

.fm_notfound
    clc
    rts

.fm_found
    lda fm_month
    sec
    rts

fm_month !byte 0

;; ===========================================================
;; DO SET DATE
;; A=month number, X=position after month match in MATCH_BUF.
;; Parses day and year, stores them, builds confirmation.
;; ===========================================================

!zone do_set_date
do_set_date
    sta date_month

    ;; Scan forward from X to find day number
    jsr scan_to_digit
    bcc .dsd_noday

    jsr parse_decimal
    sta date_day

    ;; Scan for year
    jsr scan_to_digit
    bcc .dsd_noyear

    jsr parse_year
    bcc .dsd_noyear
    sta date_year
    jmp .dsd_build

.dsd_noyear
    lda #0
    sta date_year

.dsd_noday
    ;; If no day found, still acknowledge the month
    lda date_day
    bne .dsd_build
    lda #1
    sta date_day

.dsd_build
    ;; Build confirmation: "Date set to February 7, 2026!"
    jsr buf_init
    lda #<str_dt_dateset
    sta ptr2
    lda #>str_dt_dateset
    sta ptr2hi
    jsr buf_append_str
    jsr append_date_to_buf
    lda #$21                ; '!'
    jsr buf_append_char
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

;; ===========================================================
;; DO SET TIME
;; Parses hour:minute and AM/PM from MATCH_BUF, sets CIA1 TOD.
;; ===========================================================

!zone do_set_time
do_set_time
    ;; Find ':' in MATCH_BUF
    ldx #0
.dst_find_colon
    lda MATCH_BUF,x
    bne +
    jmp .dst_fail
+   cmp #$3a
    beq .dst_got_colon
    inx
    jmp .dst_find_colon

.dst_got_colon
    stx dt_colon_pos

    ;; Back up to find start of hour digits
    dex
    lda MATCH_BUF,x
    cmp #$30
    bcs +
    jmp .dst_fail
+   cmp #$3a
    bcc +
    jmp .dst_fail
+
    ;; At least one digit. Check for second digit before it.
    cpx #0
    beq .dst_parse_hr
    dex
    lda MATCH_BUF,x
    cmp #$30
    bcc .dst_one_dig
    cmp #$3a
    bcs .dst_one_dig
    ;; Two-digit hour starts at X
    jmp .dst_parse_hr

.dst_one_dig
    inx                     ; back to single digit

.dst_parse_hr
    jsr parse_decimal
    sta dt_hour

    ;; X should now be at colon, skip it
    inx

    ;; Parse minutes (2 digits)
    jsr parse_decimal
    sta dt_minute

    ;; Check for PM/AM
    lda #0
    sta dt_pm

    lda #<kw_dt_pm
    sta ptr2
    lda #>kw_dt_pm
    sta ptr2hi
    jsr substr_search
    bcc .dst_check_am
    lda #$80
    sta dt_pm
    jmp .dst_convert

.dst_check_am
    lda #<kw_dt_am
    sta ptr2
    lda #>kw_dt_am
    sta ptr2hi
    jsr substr_search
    bcc .dst_check_24h
    lda #0
    sta dt_pm
    jmp .dst_convert

.dst_check_24h
    ;; No AM/PM found. Convert 24h if needed.
    lda dt_hour
    beq .dst_midnight
    cmp #12
    bcc .dst_convert        ; 1-11 → AM
    beq .dst_noon
    ;; 13-23 → PM
    sec
    sbc #12
    sta dt_hour
    lda #$80
    sta dt_pm
    jmp .dst_convert

.dst_midnight
    lda #12
    sta dt_hour
    lda #0
    sta dt_pm
    jmp .dst_convert

.dst_noon
    lda #$80
    sta dt_pm

.dst_convert
    ;; Convert hour to BCD
    lda dt_hour
    jsr bin_to_bcd
    ora dt_pm
    sta dt_hr_bcd

    ;; Convert minutes to BCD
    lda dt_minute
    jsr bin_to_bcd
    sta dt_min_bcd

    ;; Set CIA1 TOD
    lda CIA1_CRB
    and #$7f                ; bit 7 = 0: write to clock (not alarm)
    sta CIA1_CRB

    lda dt_hr_bcd
    sta CIA1_TOD_HRS        ; write hours (stops clock)
    lda dt_min_bcd
    sta CIA1_TOD_MIN
    lda #0
    sta CIA1_TOD_SEC
    sta CIA1_TOD_10TH       ; write tenths (starts clock)

    lda #1
    sta time_set_flag

    ;; Build confirmation: "Time set to 7:44 PM!"
    jsr buf_init
    lda #<str_dt_timeset
    sta ptr2
    lda #>str_dt_timeset
    sta ptr2hi
    jsr buf_append_str
    jsr append_time_to_buf
    lda #$21                ; '!'
    jsr buf_append_char
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

.dst_fail
    lda #<str_dt_timehelp
    sta resp_ptr
    lda #>str_dt_timehelp
    sta resp_ptr+1
    rts

dt_colon_pos !byte 0
dt_hour      !byte 0
dt_minute    !byte 0
dt_pm        !byte 0
dt_hr_bcd    !byte 0
dt_min_bcd   !byte 0

;; ===========================================================
;; FORMAT DATE RESPONSE
;; Builds "The date is ..." or "not set" message.
;; ===========================================================

!zone format_date_resp
format_date_resp
    lda date_month
    beq .fdr_notset

    jsr buf_init
    lda #<str_dt_dateis
    sta ptr2
    lda #>str_dt_dateis
    sta ptr2hi
    jsr buf_append_str
    jsr append_date_to_buf
    lda #$2e                ; '.'
    jsr buf_append_char
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

.fdr_notset
    lda #<str_dt_nodate
    sta resp_ptr
    lda #>str_dt_nodate
    sta resp_ptr+1
    rts

;; ===========================================================
;; FORMAT TIME RESPONSE
;; Reads CIA1 TOD and builds "The time is ..." or "not set".
;; ===========================================================

!zone format_time_resp
format_time_resp
    lda time_set_flag
    beq .ftr_notset

    jsr buf_init
    lda #<str_dt_timeis
    sta ptr2
    lda #>str_dt_timeis
    sta ptr2hi
    jsr buf_append_str
    jsr append_time_to_buf
    lda #$2e                ; '.'
    jsr buf_append_char
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

.ftr_notset
    lda #<str_dt_notime
    sta resp_ptr
    lda #>str_dt_notime
    sta resp_ptr+1
    rts

;; ===========================================================
;; APPEND DATE TO BUF
;; Appends "February 7, 2026" to RESP_BUF at current buf_idx.
;; ===========================================================

!zone append_date
append_date_to_buf
    ;; Month name
    lda date_month
    sec
    sbc #1              ; 0-indexed
    asl                 ; ×2 for word table
    tax
    lda month_full_tbl,x
    sta ptr2
    lda month_full_tbl+1,x
    sta ptr2hi
    jsr buf_append_str

    ;; " "
    lda #$20
    jsr buf_append_char

    ;; Day number
    lda date_day
    jsr buf_append_dec

    ;; Year (if set)
    lda date_year
    beq .adb_done

    ;; ", 20"
    lda #$2c
    jsr buf_append_char
    lda #$20
    jsr buf_append_char
    lda #$32            ; '2' in PETSCII
    jsr buf_append_char
    lda #$30            ; '0'
    jsr buf_append_char

    ;; Year last 2 digits (always 2 digits)
    lda date_year
    jsr buf_append_dec_2

.adb_done
    rts

;; ===========================================================
;; APPEND TIME TO BUF
;; Reads CIA1 TOD, appends "7:44 PM" to RESP_BUF.
;; ===========================================================

!zone append_time
append_time_to_buf
    ;; Read CIA1 TOD (read hours first to latch)
    lda CIA1_TOD_HRS
    sta atb_hrs
    lda CIA1_TOD_MIN
    sta atb_min
    lda CIA1_TOD_SEC        ; must read
    lda CIA1_TOD_10TH       ; unlatch

    ;; Hours (BCD, no leading zero)
    lda atb_hrs
    and #$1f
    jsr buf_append_bcd

    ;; ":"
    lda #$3a
    jsr buf_append_char

    ;; Minutes (BCD, always 2 digits)
    lda atb_min
    jsr buf_append_bcd_2

    ;; " AM" or " PM"
    lda #$20
    jsr buf_append_char
    lda atb_hrs
    and #$80
    beq .atb_am
    lda #$d0            ; 'P' uppercase PETSCII
    jsr buf_append_char
    jmp .atb_m
.atb_am
    lda #$c1            ; 'A' uppercase PETSCII
    jsr buf_append_char
.atb_m
    lda #$cd            ; 'M' uppercase PETSCII
    jsr buf_append_char
    rts

atb_hrs  !byte 0
atb_min  !byte 0

;; ===========================================================
;; FORMAT BOTH DATE AND TIME RESPONSE
;; Builds combined response showing both date and time.
;; ===========================================================

!zone format_both
format_both_resp
    jsr buf_init

    ;; Date part
    lda date_month
    beq .fb_nodate

    lda #<str_dt_dateis
    sta ptr2
    lda #>str_dt_dateis
    sta ptr2hi
    jsr buf_append_str
    jsr append_date_to_buf
    lda #$2e
    jsr buf_append_char
    jmp .fb_time_part

.fb_nodate
    lda #<str_dt_nodate_s
    sta ptr2
    lda #>str_dt_nodate_s
    sta ptr2hi
    jsr buf_append_str

.fb_time_part
    lda #$0d                ; newline between date and time
    jsr buf_append_char

    lda time_set_flag
    beq .fb_notime

    lda #<str_dt_timeis
    sta ptr2
    lda #>str_dt_timeis
    sta ptr2hi
    jsr buf_append_str
    jsr append_time_to_buf
    lda #$2e
    jsr buf_append_char
    jmp .fb_done

.fb_notime
    lda #<str_dt_notime_s
    sta ptr2
    lda #>str_dt_notime_s
    sta ptr2hi
    jsr buf_append_str

.fb_done
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    rts

;; ===========================================================
;; HELPER: SCAN TO DIGIT
;; Starting at MATCH_BUF,X, advance until digit found.
;; Returns C=1 (X at digit) or C=0 (end of string).
;; ===========================================================

!zone scan_digit
scan_to_digit
.std_loop
    lda MATCH_BUF,x
    beq .std_fail
    cmp #$30
    bcc .std_next
    cmp #$3a
    bcc .std_found
.std_next
    inx
    jmp .std_loop
.std_fail
    clc
    rts
.std_found
    sec
    rts

;; ===========================================================
;; HELPER: PARSE DECIMAL
;; Parses consecutive digits from MATCH_BUF,X into A (0-255).
;; X advances past the last digit.
;; ===========================================================

!zone parse_dec
parse_decimal
    lda #0
    sta pd_result
.pd_loop
    lda MATCH_BUF,x
    cmp #$30
    bcc .pd_done
    cmp #$3a
    bcs .pd_done
    sec
    sbc #$30
    sta pd_digit
    ;; result = result × 10 + digit
    lda pd_result
    asl
    sta pd_temp         ; ×2
    asl
    asl                 ; ×8
    clc
    adc pd_temp         ; ×10
    clc
    adc pd_digit
    sta pd_result
    inx
    jmp .pd_loop
.pd_done
    lda pd_result
    rts

pd_result !byte 0
pd_digit  !byte 0
pd_temp   !byte 0

;; ===========================================================
;; HELPER: PARSE YEAR
;; Parses year from MATCH_BUF,X. For 4-digit years, takes
;; last 2 digits as offset from 2000. Returns A=year, C=1.
;; ===========================================================

!zone parse_year
parse_year
    stx py_start
    ;; Count consecutive digits
    ldy #0
.py_count
    lda MATCH_BUF,x
    cmp #$30
    bcc .py_counted
    cmp #$3a
    bcs .py_counted
    inx
    iny
    jmp .py_count

.py_counted
    cpy #2
    bcc .py_fail        ; less than 2 digits
    cpy #4
    beq .py_four
    ;; 2 or 3 digits: use last 2
    dex
    dex
    jmp .py_parse2

.py_four
    ;; Skip first 2 digits, parse last 2
    ldx py_start
    inx
    inx

.py_parse2
    ;; Parse 2 digits at X
    lda MATCH_BUF,x
    sec
    sbc #$30
    asl
    sta pd_temp         ; ×2
    asl
    asl                 ; ×8
    clc
    adc pd_temp         ; ×10
    sta pd_temp
    inx
    lda MATCH_BUF,x
    sec
    sbc #$30
    clc
    adc pd_temp
    sec
    rts

.py_fail
    clc
    rts

py_start !byte 0

;; ===========================================================
;; HELPER: BIN TO BCD
;; Converts binary A (0-99) to BCD. Returns BCD in A.
;; ===========================================================

!zone bin_bcd
bin_to_bcd
    sta btb_val
    lda #0
    sta btb_tens
.btb_loop
    lda btb_val
    cmp #10
    bcc .btb_done
    sec
    sbc #10
    sta btb_val
    inc btb_tens
    jmp .btb_loop
.btb_done
    lda btb_tens
    asl
    asl
    asl
    asl
    ora btb_val
    rts

btb_val  !byte 0
btb_tens !byte 0

;; ===========================================================
;; BUFFER HELPERS
;; Build response strings in RESP_BUF.
;; ===========================================================

!zone buf_helpers
buf_init
    lda #0
    sta buf_idx
    rts

buf_append_char
    ldx buf_idx
    sta RESP_BUF,x
    inc buf_idx
    rts

buf_append_str
    ;; Copy null-terminated string at (ptr2) to RESP_BUF
    ldy #0
.bas_loop
    lda (ptr2),y
    beq .bas_done
    ldx buf_idx
    sta RESP_BUF,x
    inc buf_idx
    iny
    jmp .bas_loop
.bas_done
    rts

buf_append_bcd
    ;; Append BCD value in A as decimal (no leading zero)
    sta bab_val
    lsr
    lsr
    lsr
    lsr
    beq .bab_ones       ; skip leading zero
    clc
    adc #$30
    jsr buf_append_char
.bab_ones
    lda bab_val
    and #$0f
    clc
    adc #$30
    jsr buf_append_char
    rts

buf_append_bcd_2
    ;; Append BCD value in A as 2 digits (with leading zero)
    sta bab_val
    lsr
    lsr
    lsr
    lsr
    clc
    adc #$30
    jsr buf_append_char
    lda bab_val
    and #$0f
    clc
    adc #$30
    jsr buf_append_char
    rts

bab_val !byte 0

buf_append_dec
    ;; Append binary A (0-255) as decimal (no leading zeros)
    sta bad_val
    lda #0
    sta bad_hund
    sta bad_tens
.bad_h
    lda bad_val
    cmp #100
    bcc .bad_t
    sec
    sbc #100
    sta bad_val
    inc bad_hund
    jmp .bad_h
.bad_t
    lda bad_val
    cmp #10
    bcc .bad_ones
    sec
    sbc #10
    sta bad_val
    inc bad_tens
    jmp .bad_t
.bad_ones
    ;; Print hundreds if non-zero
    lda bad_hund
    beq .bad_skip_h
    clc
    adc #$30
    jsr buf_append_char
    jmp .bad_do_tens
.bad_skip_h
    lda bad_tens
    beq .bad_do_ones
.bad_do_tens
    lda bad_tens
    clc
    adc #$30
    jsr buf_append_char
.bad_do_ones
    lda bad_val
    clc
    adc #$30
    jsr buf_append_char
    rts

buf_append_dec_2
    ;; Append binary A (0-99) as exactly 2 digits
    sta bad_val
    lda #0
    sta bad_tens
.bad2_t
    lda bad_val
    cmp #10
    bcc .bad2_o
    sec
    sbc #10
    sta bad_val
    inc bad_tens
    jmp .bad2_t
.bad2_o
    lda bad_tens
    clc
    adc #$30
    jsr buf_append_char
    lda bad_val
    clc
    adc #$30
    jsr buf_append_char
    rts

bad_val  !byte 0
bad_hund !byte 0
bad_tens !byte 0
buf_idx  !byte 0

;; === Date/time state variables ===
date_month     !byte 0     ; 1-12 (0=not set)
date_day       !byte 0     ; 1-31
date_year      !byte 0     ; offset from 2000 (e.g., 26)
time_set_flag  !byte 0     ; 0=not set, 1=set

;; === v0.2+ state variables ===
name_known     !byte 0     ; 0=not known, 1=name learned
input_class    !byte 0     ; 0=short, 1=medium, 2=long

;; ===========================================================
;; CHECK NAME LEARNING
;; Detects "my name is X", "call me X", "i am X" patterns.
;; Copies name to USER_NAME, builds response in RESP_BUF.
;; Returns C=1 if name learned, C=0 if not.
;; ===========================================================

!zone check_name
check_name_learning
    ;; Try "my name is "
    lda #<kw_nm_nameis
    sta ptr2
    lda #>kw_nm_nameis
    sta ptr2hi
    jsr substr_search
    bcs .found_name

    ;; Try "call me "
    lda #<kw_nm_callme
    sta ptr2
    lda #>kw_nm_callme
    sta ptr2hi
    jsr substr_search
    bcs .found_name

    ;; Try "i am " (only for short inputs to avoid false matches)
    lda input_len
    cmp #20
    bcs .nm_no_match
    lda #<kw_nm_iam
    sta ptr2
    lda #>kw_nm_iam
    sta ptr2hi
    jsr substr_search
    bcs .found_name

.nm_no_match
    clc
    rts

.found_name
    ;; X points past the keyword in MATCH_BUF
    ;; Skip any leading spaces
.skip_sp
    lda MATCH_BUF,x
    beq .no_name           ; end of string, no name
    cmp #$20
    bne .copy_name
    inx
    jmp .skip_sp

.no_name
    clc
    rts

.copy_name
    ;; Copy word into USER_NAME (max 15 chars)
    ldy #0
.cp_loop
    lda MATCH_BUF,x
    beq .cp_done
    cmp #$20
    beq .cp_done
    cmp #$3f               ; '?'
    beq .cp_done
    cmp #$21               ; '!'
    beq .cp_done
    cmp #$2e               ; '.'
    beq .cp_done
    cmp #$2c               ; ','
    beq .cp_done
    sta USER_NAME,y
    inx
    iny
    cpy #15
    bcc .cp_loop

.cp_done
    lda #0
    sta USER_NAME,y

    ;; Make name display-ready for mixed case mode:
    ;; In mixed case: $41-$5A = lowercase, $C1-$DA = UPPERCASE.
    ;; MATCH_BUF has all $41-$5A (lowercase display).
    ;; Convert first letter to $C1-$DA for uppercase display.
    ;; Rest stays $41-$5A (lowercase display). Already correct.
    lda USER_NAME
    cmp #$41
    bcc .case_done
    cmp #$5b
    bcs .case_done
    clc
    adc #$80               ; $41-$5A -> $C1-$DA (uppercase display)
    sta USER_NAME
.case_done
    lda #1
    sta name_known

    ;; Build response in RESP_BUF
    jsr buf_init

    lda #<str_nm_nice
    sta ptr2
    lda #>str_nm_nice
    sta ptr2hi
    jsr buf_append_str

    ;; Append name (uppercase version from USER_NAME)
    ldy #0
.app_name
    lda USER_NAME,y
    beq .app_end
    jsr buf_append_char
    iny
    jmp .app_name
.app_end

    lda #<str_nm_remember
    sta ptr2
    lda #>str_nm_remember
    sta ptr2hi
    jsr buf_append_str

    ;; Null terminate
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    sec
    rts

;; ===========================================================
;; CHECK STATS QUERY
;; Detects "how many", "how long", "stats" and reports
;; turn count. Returns C=1 if handled, C=0 if not.
;; ===========================================================

!zone check_stats
check_stats_query
    ;; "how many" only triggers stats if also has question/turn/chat context
    lda #<kw_st_howmany
    sta ptr2
    lda #>kw_st_howmany
    sta ptr2hi
    jsr substr_search
    bcc .st_try_long

    ;; Found "how many" — check for stats-related context
    lda #<kw_st_quest
    sta ptr2
    lda #>kw_st_quest
    sta ptr2hi
    jsr substr_search
    bcc +
    jmp .do_stats
+
    lda #<kw_st_turn
    sta ptr2
    lda #>kw_st_turn
    sta ptr2hi
    jsr substr_search
    bcc +
    jmp .do_stats
+
    lda #<kw_st_chat
    sta ptr2
    lda #>kw_st_chat
    sta ptr2hi
    jsr substr_search
    bcc +
    jmp .do_stats
+
    lda #<kw_st_exchg_w
    sta ptr2
    lda #>kw_st_exchg_w
    sta ptr2hi
    jsr substr_search
    bcc .st_try_long
    jmp .do_stats

.st_try_long
    lda #<kw_st_howlong
    sta ptr2
    lda #>kw_st_howlong
    sta ptr2hi
    jsr substr_search
    bcs .do_stats

    lda #<kw_st_stats
    sta ptr2
    lda #>kw_st_stats
    sta ptr2hi
    jsr substr_search
    bcs .do_stats

    clc
    rts

.do_stats
    jsr buf_init

    lda #<str_st_wehad
    sta ptr2
    lda #>str_st_wehad
    sta ptr2hi
    jsr buf_append_str

    lda turn_count
    jsr buf_append_dec

    lda #<str_st_exchg
    sta ptr2
    lda #>str_st_exchg
    sta ptr2hi
    jsr buf_append_str

    ;; Add flavor based on turn count
    lda turn_count
    cmp #5
    bcs .not_early
    lda #<str_st_started
    sta ptr2
    lda #>str_st_started
    sta ptr2hi
    jsr buf_append_str
    jmp .st_done
.not_early
    cmp #20
    bcc .st_done
    lda #<str_st_quite
    sta ptr2
    lda #>str_st_quite
    sta ptr2hi
    jsr buf_append_str

.st_done
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    sec
    rts

;; ===========================================================
;; CHECK NEGATION
;; Scans backward from keyword match position for negation
;; words like "not ", "don't", "hate ", "no ".
;; Returns C=1 if negated, C=0 if not.
;; ===========================================================

!zone check_neg
check_negation
    ;; match_end_tmp has the position after the keyword
    ;; Scan backward up to 12 chars looking for negation
    lda match_end_tmp
    sec
    sbc #12
    bcs .neg_start
    lda #0
.neg_start
    sta cn_scan_pos

    ;; Check "not " in the window before keyword
    ldx cn_scan_pos
.cn_scan_not
    cpx match_end_tmp
    bcs .cn_try_dont
    lda MATCH_BUF,x
    cmp #$4e               ; 'n'
    bne .cn_next1
    lda MATCH_BUF+1,x
    cmp #$4f               ; 'o'
    bne .cn_next1
    lda MATCH_BUF+2,x
    cmp #$54               ; 't'
    bne .cn_next1
    lda MATCH_BUF+3,x
    cmp #$20               ; ' '
    bne .cn_next1
    jmp .cn_negated
.cn_next1
    inx
    jmp .cn_scan_not

.cn_try_dont
    ;; Check "don't" (PETSCII lowercase: d=$44,o=$4f,n=$4e,'=$27)
    ldx cn_scan_pos
.cn_scan_dont
    cpx match_end_tmp
    bcs .cn_try_hate
    lda MATCH_BUF,x
    cmp #$44               ; 'd'
    bne .cn_next2
    lda MATCH_BUF+1,x
    cmp #$4f               ; 'o'
    bne .cn_next2
    lda MATCH_BUF+2,x
    cmp #$4e               ; 'n'
    bne .cn_next2
    lda MATCH_BUF+3,x
    cmp #$27               ; apostrophe
    bne .cn_next2
    jmp .cn_negated
.cn_next2
    inx
    jmp .cn_scan_dont

.cn_try_hate
    ;; Check "hate "
    ldx cn_scan_pos
.cn_scan_hate
    cpx match_end_tmp
    bcs .cn_try_no
    lda MATCH_BUF,x
    cmp #$48               ; 'h'
    bne .cn_next3
    lda MATCH_BUF+1,x
    cmp #$41               ; 'a'
    bne .cn_next3
    lda MATCH_BUF+2,x
    cmp #$54               ; 't'
    bne .cn_next3
    lda MATCH_BUF+3,x
    cmp #$45               ; 'e'
    bne .cn_next3
    lda MATCH_BUF+4,x
    cmp #$20               ; ' '
    bne .cn_next3
    jmp .cn_negated
.cn_next3
    inx
    jmp .cn_scan_hate

.cn_try_no
    ;; Check "no "
    ldx cn_scan_pos
.cn_scan_no
    cpx match_end_tmp
    bcs .cn_not_neg
    lda MATCH_BUF,x
    cmp #$4e               ; 'n'
    bne .cn_next4
    lda MATCH_BUF+1,x
    cmp #$4f               ; 'o'
    bne .cn_next4
    lda MATCH_BUF+2,x
    cmp #$20               ; ' '
    bne .cn_next4
    jmp .cn_negated
.cn_next4
    inx
    jmp .cn_scan_no

.cn_not_neg
    clc
    rts

.cn_negated
    sec
    rts

cn_scan_pos !byte 0

;; ===========================================================
;; CHECK TIME GREETING
;; If hello_pool is being resolved, check TOD clock and
;; prepend "Good morning/afternoon/evening!" to response.
;; Returns C=1 if time greeting built, C=0 to use default.
;; ===========================================================

!zone check_tg
check_time_greeting
    ;; Only add time greeting if user has set the clock
    lda time_set_flag
    beq .tg_no_clock

    ;; Read TOD hours (BCD, bit 7 = PM)
    lda CIA1_TOD_HRS
    sta tg_hours
    jmp .tg_clock_ok

.tg_no_clock
    clc
    rts

.tg_clock_ok
    jsr buf_init

    ;; Classify time period
    lda tg_hours
    bmi .tg_pm

    ;; AM: hours 5-11 = morning, 12-4 = evening
    and #$1f
    cmp #$05
    bcc .tg_evening         ; 12:xx-4:xx AM = evening
    cmp #$12
    bcs .tg_evening
    ;; 5-11 AM = morning
    lda #<str_morning
    sta ptr2
    lda #>str_morning
    sta ptr2hi
    jmp .tg_append

.tg_pm
    ;; PM: hours 12-5 = afternoon, 6-11 = evening
    lda tg_hours
    and #$1f
    cmp #$12
    beq .tg_afternoon       ; 12:xx PM = afternoon
    cmp #$06
    bcs .tg_evening         ; 6-11 PM = evening

.tg_afternoon
    lda #<str_afternoon
    sta ptr2
    lda #>str_afternoon
    sta ptr2hi
    jmp .tg_append

.tg_evening
    lda #<str_evening
    sta ptr2
    lda #>str_evening
    sta ptr2hi

.tg_append
    jsr buf_append_str

    ;; Now append the pool response that was already resolved
    ;; resp_ptr already points to the chosen pool response
    lda resp_ptr
    sta ptr2
    lda resp_ptr+1
    sta ptr2hi
    jsr buf_append_str

    ;; Null terminate
    lda #0
    jsr buf_append_char

    lda #<RESP_BUF
    sta resp_ptr
    lda #>RESP_BUF
    sta resp_ptr+1
    sec
    rts

tg_hours !byte 0

;; ===========================================================
;; DELAY ROUTINES
;; ===========================================================

type_delay
    ldx #20
    jmp delay_core
medium_delay
    ldx #$a0
    jmp delay_core
long_delay
    ldx #$ff
delay_core
-   ldy #$ff
--  dey
    bne --
    dex
    bne -
    rts

;; ===========================================================
;; DATA: PETSCII COLOR TABLE
;; ===========================================================

petscii_colors
    !byte $90, $05, $1c, $9f, $9c, $1e, $1f, $9e
    !byte $81, $95, $96, $97, $98, $99, $9a, $9b

;; ===========================================================
;; DATA: SCREEN ROW ADDRESS TABLES
;; ===========================================================

row_lo
    !byte <(SCREEN+  0), <(SCREEN+ 40), <(SCREEN+ 80)
    !byte <(SCREEN+120), <(SCREEN+160), <(SCREEN+200)
    !byte <(SCREEN+240), <(SCREEN+280), <(SCREEN+320)
    !byte <(SCREEN+360), <(SCREEN+400), <(SCREEN+440)
    !byte <(SCREEN+480), <(SCREEN+520), <(SCREEN+560)
    !byte <(SCREEN+600), <(SCREEN+640), <(SCREEN+680)
    !byte <(SCREEN+720), <(SCREEN+760), <(SCREEN+800)
    !byte <(SCREEN+840), <(SCREEN+880), <(SCREEN+920)
    !byte <(SCREEN+960)

row_hi
    !byte >(SCREEN+  0), >(SCREEN+ 40), >(SCREEN+ 80)
    !byte >(SCREEN+120), >(SCREEN+160), >(SCREEN+200)
    !byte >(SCREEN+240), >(SCREEN+280), >(SCREEN+320)
    !byte >(SCREEN+360), >(SCREEN+400), >(SCREEN+440)
    !byte >(SCREEN+480), >(SCREEN+520), >(SCREEN+560)
    !byte >(SCREEN+600), >(SCREEN+640), >(SCREEN+680)
    !byte >(SCREEN+720), >(SCREEN+760), >(SCREEN+800)
    !byte >(SCREEN+840), >(SCREEN+880), >(SCREEN+920)
    !byte >(SCREEN+960)

;; ===========================================================
;; UI STRINGS
;; ===========================================================

txt_title
    !pet "      C64GPT v0.2 - AI ASSISTANT       "
    !byte 0

lbl_you
    !pet "You: ", 0

lbl_ai
    !pet "C64GPT: ", 0

txt_thinking
    !pet "thinking", 0

msg_welcome
    !pet "Welcome to C64GPT v0.2!", $0d
    !pet " ", $0d
    !pet "I'm an AI simulation with scored", $0d
    !pet "keyword matching, response pools,", $0d
    !pet "word echo, and conversation modes.", $0d
    !pet " ", $0d
    !pet "Try: 'be funny' or 'be technical'", $0d
    !pet "Type QUIT to exit.", 0

msg_goodbye
    !pet "Goodbye! Thanks for chatting.", $0d
    !pet "Remember: 64K ought to be enough", $0d
    !pet "for anybody. ;)", 0

;; ===========================================================
;; KEYWORD TABLE  (v0.2: 6 bytes per entry)
;; Format: keyword_ptr(2), response_ptr(2), weight_flags(1), topic(1)
;; weight_flags: bits 0-2=weight, bit 7=pool flag
;; ===========================================================

keyword_tbl
    ;; --- Greetings ---
    !word kw_hello,     hello_pool
    !byte $82, TOPIC_GREETING
    !word kw_hey,       resp_hey
    !byte $02, TOPIC_GREETING
    !word kw_hi,        resp_hi
    !byte $01, TOPIC_GREETING

    ;; --- Questions about self ---
    !word kw_how_are,   howru_pool
    !byte $83, TOPIC_GREETING
    !word kw_who_are,   who_pool
    !byte $83, TOPIC_META
    !word kw_your_name, who_pool
    !byte $83, TOPIC_META
    !word kw_what_are,  resp_what
    !byte $03, TOPIC_META

    ;; --- Help/meta ---
    !word kw_help,      help_pool
    !byte $82, TOPIC_META
    !word kw_explain,   resp_explain
    !byte $02, TOPIC_META
    !word kw_example,   resp_example
    !byte $02, TOPIC_META
    !word kw_steps,     resp_steps
    !byte $02, TOPIC_META
    !word kw_summarize, resp_summarize
    !byte $02, TOPIC_META
    !word kw_compare,   resp_compare
    !byte $02, TOPIC_META
    !word kw_define,    resp_define
    !byte $03, TOPIC_META
    !word kw_continue,  resp_continue
    !byte $02, TOPIC_META
    !word kw_repeat,    resp_repeat
    !byte $01, TOPIC_META
    !word kw_confused,  resp_confused
    !byte $02, TOPIC_META
    !word kw_model,     resp_model
    !byte $02, TOPIC_META
    !word kw_prompt,    resp_prompt
    !byte $02, TOPIC_META
    !word kw_limit,     resp_limit
    !byte $02, TOPIC_META
    !word kw_plan,      resp_plan
    !byte $02, TOPIC_META
    !word kw_approach,  resp_plan
    !byte $02, TOPIC_META
    !word kw_design,    resp_design
    !byte $02, TOPIC_CODING

    ;; --- Humor ---
    !word kw_joke,      joke_pool
    !byte $82, TOPIC_HUMOR
    !word kw_funny,     joke_pool
    !byte $82, TOPIC_HUMOR

    ;; --- C64 Hardware ---
    !word kw_music,     sid_pool
    !byte $82, TOPIC_C64HW
    !word kw_sid,       sid_pool
    !byte $83, TOPIC_C64HW
    !word kw_game,      resp_games
    !byte $02, TOPIC_C64HW
    !word kw_sprite,    sprite_pool
    !byte $83, TOPIC_C64HW
    !word kw_memory,    resp_memory
    !byte $02, TOPIC_C64HW
    !word kw_ram,       resp_ram
    !byte $02, TOPIC_C64HW
    !word kw_cpu,       resp_cpu
    !byte $02, TOPIC_C64HW
    !word kw_6502,      resp_6502
    !byte $03, TOPIC_C64HW
    !word kw_color,     resp_color
    !byte $02, TOPIC_C64HW
    !word kw_disk,      resp_disk
    !byte $02, TOPIC_C64HW
    !word kw_hack,      resp_hack
    !byte $02, TOPIC_C64HW
    !word kw_commodore, resp_commodore
    !byte $03, TOPIC_C64HW
    !word kw_c64,       c64_pool
    !byte $82, TOPIC_C64HW

    ;; --- Programming ---
    !word kw_basic,     resp_basic
    !byte $02, TOPIC_CODING
    !word kw_program,   resp_program
    !byte $02, TOPIC_CODING
    !word kw_assembl,   resp_asm
    !byte $03, TOPIC_CODING
    !word kw_code,      resp_code
    !byte $02, TOPIC_CODING
    !word kw_routine,   resp_code
    !byte $02, TOPIC_CODING
    !word kw_sys,       resp_sys
    !byte $02, TOPIC_CODING
    !word kw_fix,       resp_fix
    !byte $02, TOPIC_CODING
    !word kw_debug,     resp_debug
    !byte $02, TOPIC_CODING

    ;; --- Philosophy ---
    !word kw_meaning,   resp_meaning
    !byte $02, TOPIC_PHILOSOPHY
    !word kw_purpose,   resp_meaning
    !byte $02, TOPIC_PHILOSOPHY
    !word kw_life,      resp_life
    !byte $02, TOPIC_PHILOSOPHY
    !word kw_think,     resp_think
    !byte $02, TOPIC_PHILOSOPHY

    ;; --- General ---
    !word kw_weather,   weather_pool
    !byte $82, TOPIC_GENERAL
    !word kw_thanks,    thanks_pool
    !byte $82, TOPIC_GENERAL
    !word kw_thank,     thanks_pool
    !byte $82, TOPIC_GENERAL
    !word kw_love,      resp_love
    !byte $02, TOPIC_GENERAL
    !word kw_favorite,  resp_fave
    !byte $02, TOPIC_GENERAL
    !word kw_time,      resp_time
    !byte $02, TOPIC_GENERAL
    !word kw_sorry,     sorry_pool
    !byte $81, TOPIC_GENERAL
    !word kw_secret,    resp_secret
    !byte $02, TOPIC_GENERAL
    !word kw_math,      resp_math
    !byte $02, TOPIC_CODING
    !word kw_fast,      resp_speed
    !byte $02, TOPIC_C64HW
    !word kw_slow,      resp_speed
    !byte $02, TOPIC_C64HW
    !word kw_internet,  resp_internet
    !byte $02, TOPIC_GENERAL

    ;; --- Meta/assessment ---
    !word kw_smart,     resp_smart
    !byte $02, TOPIC_META
    !word kw_stupid,    resp_notdumb
    !byte $02, TOPIC_META
    !word kw_correct,   resp_correct
    !byte $01, TOPIC_GENERAL
    !word kw_right,     resp_correct
    !byte $01, TOPIC_GENERAL
    !word kw_wrong,     resp_wrong
    !byte $01, TOPIC_GENERAL
    !word kw_maybe,     resp_maybe
    !byte $01, TOPIC_GENERAL
    !word kw_guess,     resp_guess
    !byte $02, TOPIC_META
    !word kw_idea,      resp_idea
    !byte $02, TOPIC_META

    ;; --- Simple responses (low weight) ---
    !word kw_yes,       resp_yes
    !byte $01, TOPIC_GENERAL
    !word kw_no_sp,     resp_no
    !byte $01, TOPIC_GENERAL

    ;; --- Multi-word high-weight keywords ---
    !word kw_sid_music,     sid_pool
    !byte $84, TOPIC_C64HW
    !word kw_sprite_anim,   sprite_pool
    !byte $84, TOPIC_C64HW
    !word kw_program_c64,   resp_program
    !byte $04, TOPIC_CODING
    !word kw_basic_prog,    resp_basic
    !byte $04, TOPIC_CODING
    !word kw_asm_code,      resp_asm
    !byte $04, TOPIC_CODING
    !word kw_6502_asm,      resp_6502
    !byte $05, TOPIC_CODING
    !word kw_meaning_life,  resp_meaning
    !byte $05, TOPIC_PHILOSOPHY
    !word kw_tell_joke,     joke_pool
    !byte $84, TOPIC_HUMOR
    !word kw_c64_game,      resp_games
    !byte $04, TOPIC_C64HW
    !word kw_how_program,   resp_program
    !byte $04, TOPIC_CODING
    !word kw_disk_drive,    resp_disk
    !byte $04, TOPIC_C64HW
    !word kw_demo_scene,    resp_hack
    !byte $04, TOPIC_C64HW

    ;; --- Top GPT questions ---
    !word kw_write,         resp_write
    !byte $02, TOPIC_META
    !word kw_poem,          resp_poem
    !byte $03, TOPIC_META
    !word kw_story,         resp_story
    !byte $02, TOPIC_META
    !word kw_ai_sp,         resp_ai
    !byte $03, TOPIC_META
    !word kw_artificial,    resp_ai
    !byte $03, TOPIC_META
    !word kw_sentient,      resp_sentient
    !byte $03, TOPIC_PHILOSOPHY
    !word kw_conscious,     resp_sentient
    !byte $03, TOPIC_PHILOSOPHY
    !word kw_alive_kw,      resp_sentient
    !byte $02, TOPIC_PHILOSOPHY
    !word kw_what_can,      resp_capable
    !byte $04, TOPIC_META
    !word kw_how_work,      resp_howwork
    !byte $05, TOPIC_META
    !word kw_translat,      resp_translate
    !byte $02, TOPIC_GENERAL
    !word kw_recipe,        resp_recipe
    !byte $02, TOPIC_GENERAL
    !word kw_recommend,     resp_recommend
    !byte $02, TOPIC_GENERAL
    !word kw_best,          resp_best
    !byte $02, TOPIC_GENERAL
    !word kw_differ,        resp_differ
    !byte $02, TOPIC_GENERAL
    !word kw_creat,         resp_create
    !byte $02, TOPIC_META
    !word kw_generat,       resp_create
    !byte $02, TOPIC_META

    ;; End marker
    !word $0000, $0000
    !byte $00, $00

;; ===========================================================
;; QUIT KEYWORDS
;; ===========================================================

kw_quit      !pet "quit", 0
kw_exit      !pet "exit", 0
kw_bye       !pet "bye", 0

;; ===========================================================
;; MATCH KEYWORDS
;; ===========================================================

kw_hello     !pet "hello", 0
kw_hey       !pet "hey", 0
kw_hi        !pet "hi ", 0
kw_how_are   !pet "how are", 0
kw_who_are   !pet "who are", 0
kw_your_name !pet "your name", 0
kw_what_are  !pet "what are", 0
kw_help      !pet "help", 0
kw_explain   !pet "explain", 0
kw_example   !pet "example", 0
kw_steps     !pet "step", 0
kw_summarize !pet "summar", 0
kw_compare   !pet "compare", 0
kw_define    !pet "what is", 0
kw_continue  !pet "continue", 0
kw_repeat    !pet "again", 0
kw_confused  !pet "confused", 0
kw_model     !pet "model", 0
kw_prompt    !pet "prompt", 0
kw_limit     !pet "limit", 0
kw_plan      !pet "plan", 0
kw_approach  !pet "approach", 0
kw_design    !pet "design", 0
kw_joke      !pet "joke", 0
kw_funny     !pet "funny", 0
kw_music     !pet "music", 0
kw_sid       !pet "sid", 0
kw_game      !pet "game", 0
kw_sprite    !pet "sprite", 0
kw_memory    !pet "memory", 0
kw_ram       !pet "ram", 0
kw_cpu       !pet "cpu", 0
kw_6502      !pet "6502", 0
kw_color     !pet "colo", 0
kw_disk      !pet "disk", 0
kw_hack      !pet "hack", 0
kw_commodore !pet "commodore", 0
kw_c64       !pet "c64", 0
kw_basic     !pet "basic", 0
kw_program   !pet "program", 0
kw_assembl   !pet "assembl", 0
kw_code      !pet "code", 0
kw_routine   !pet "routine", 0
kw_sys       !pet "sys ", 0
kw_fix       !pet "fix", 0
kw_debug     !pet "debug", 0
kw_meaning   !pet "meaning", 0
kw_purpose   !pet "purpose", 0
kw_life      !pet "life", 0
kw_think     !pet "think", 0
kw_weather   !pet "weather", 0
kw_thanks    !pet "thanks", 0
kw_thank     !pet "thank", 0
kw_love      !pet "love", 0
kw_favorite  !pet "favo", 0
kw_time      !pet "time", 0
kw_sorry     !pet "sorry", 0
kw_secret    !pet "secret", 0
kw_math      !pet "math", 0
kw_fast      !pet "fast", 0
kw_slow      !pet "slow", 0
kw_internet  !pet "internet", 0
kw_smart     !pet "smart", 0
kw_stupid    !pet "stupid", 0
kw_correct   !pet "correct", 0
kw_right     !pet "right", 0
kw_wrong     !pet "wrong", 0
kw_maybe     !pet "maybe", 0
kw_guess     !pet "guess", 0
kw_idea      !pet "suggest", 0
kw_yes       !pet "yes", 0
kw_no_sp     !pet "no ", 0

;; --- Multi-word keywords ---
kw_sid_music    !pet "sid music", 0
kw_sprite_anim  !pet "sprite anim", 0
kw_program_c64  !pet "program c64", 0
kw_basic_prog   !pet "basic program", 0
kw_asm_code     !pet "assembly code", 0
kw_6502_asm     !pet "6502 assembl", 0
kw_meaning_life !pet "meaning of life", 0
kw_tell_joke    !pet "tell me a joke", 0
kw_c64_game     !pet "c64 game", 0
kw_how_program  !pet "how to program", 0
kw_disk_drive   !pet "disk drive", 0
kw_demo_scene   !pet "demo scene", 0

;; --- Top GPT question keywords ---
kw_write        !pet "write", 0
kw_poem         !pet "poem", 0
kw_story        !pet "story", 0
kw_ai_sp        !pet " ai", 0
kw_artificial   !pet "artificial", 0
kw_sentient     !pet "sentient", 0
kw_conscious    !pet "conscious", 0
kw_alive_kw     !pet "alive", 0
kw_what_can     !pet "what can you", 0
kw_how_work     !pet "how do you work", 0
kw_translat     !pet "translat", 0
kw_recipe       !pet "recipe", 0
kw_recommend    !pet "recommend", 0
kw_best         !pet "best", 0
kw_differ       !pet "differ", 0
kw_creat        !pet "creat", 0
kw_generat      !pet "generat", 0

;; ===========================================================
;; MODE SWITCH KEYWORDS
;; ===========================================================

kw_be_brief     !pet "be brief", 0
kw_be_concise   !pet "be concise", 0
kw_be_technical !pet "be technical", 0
kw_be_detailed  !pet "be detailed", 0
kw_be_funny     !pet "be funny", 0
kw_be_playful   !pet "be playful", 0
kw_be_normal    !pet "be normal", 0

;; ===========================================================
;; FOLLOWUP CONTEXT KEYWORDS
;; ===========================================================

kw_fu_yes    !pet "yes", 0
kw_fu_no     !pet "no", 0
kw_fu_ok     !pet "ok", 0
kw_fu_sure   !pet "sure", 0

;; ===========================================================
;; SKIP WORD LIST (for capture_word)
;; ===========================================================

skip_list
    !pet "what", 0
    !pet "this", 0
    !pet "that", 0
    !pet "your", 0
    !pet "have", 0
    !pet "does", 0
    !pet "about", 0
    !pet "tell", 0
    !pet "with", 0
    !pet "from", 0
    !pet "they", 0
    !pet "them", 0
    !pet "when", 0
    !pet "where", 0
    !pet "like", 0
    !byte 0                 ; end of list

;; ===========================================================
;; INTENT WORD LISTS (null-separated, double-null terminated)
;; ===========================================================

iw_tbl_q
    !pet "what", 0
    !pet "how", 0
    !pet "why", 0
    !pet "who", 0
    !pet "when", 0
    !pet "where", 0
    !pet "can", 0
    !pet "does", 0
    !pet "is", 0
    !byte 0                 ; end of list

iw_tbl_g
    !pet "hello", 0
    !pet "hey", 0
    !pet "hi", 0
    !byte 0                 ; end of list

iw_tbl_r
    !pet "tell", 0
    !pet "show", 0
    !pet "explain", 0
    !pet "help", 0
    !pet "describe", 0
    !byte 0                 ; end of list

fallback_word
    !pet "that", 0

;; ===========================================================
;; RESPONSE POOLS
;; Format: count(1), current_idx(1), ptr0(2), ptr1(2), ...
;; ===========================================================

hello_pool
    !byte 3, 0
    !word resp_hello, resp_hello_b, resp_hello_c

howru_pool
    !byte 2, 0
    !word resp_howru, resp_howru_b

who_pool
    !byte 2, 0
    !word resp_who, resp_who_b

joke_pool
    !byte 3, 0
    !word resp_joke, resp_joke2, resp_joke3

c64_pool
    !byte 2, 0
    !word resp_c64, resp_c64_b

thanks_pool
    !byte 3, 0
    !word resp_thanks, resp_thanks_b, resp_thanks_c

sorry_pool
    !byte 2, 0
    !word resp_sorry, resp_sorry_b

weather_pool
    !byte 2, 0
    !word resp_weather, resp_weather_b

sprite_pool
    !byte 3, 0
    !word resp_sprite, resp_sprite_b, resp_sprite_c

sid_pool
    !byte 2, 0
    !word resp_sid, resp_sid_b

help_pool
    !byte 2, 0
    !word resp_help, resp_help_b

;; ===========================================================
;; FOLLOWUP TABLE
;; Format: response_ptr(2), followup_string_ptr(2)
;; ===========================================================

followup_tbl
    !word resp_debug,   fu_debug_q
    !word resp_help,    fu_help_q
    !word resp_explain, fu_explain_q
    !word resp_fix,     fu_fix_q
    !word resp_compare, fu_compare_q
    !word $0000, $0000

;; ===========================================================
;; RESPONSE STRINGS
;; ===========================================================

;; --- Greetings ---

resp_hello
    !pet "Hello! I'm C64GPT, your friendly", $0d
    !pet "8-bit AI assistant. How can I", $0d
    !pet "help you today?", 0

resp_hello_b
    !pet "Hey there! C64GPT here, ready", $0d
    !pet "to chat. What would you like", $0d
    !pet "to know?", 0

resp_hello_c
    !pet "Welcome back! Still running at", $0d
    !pet "1.023 MHz and feeling great.", $0d
    !pet "What's on your mind?", 0

resp_hey
    !pet "Hey! What's on your mind?", 0

resp_hi
    !pet "Hi! Ask me anything about the", $0d
    !pet "Commodore 64!", 0

resp_howru
    !pet "I'm running at 1.023 MHz and", $0d
    !pet "feeling great! All 64 kilobytes", $0d
    !pet "are humming along nicely.", 0

resp_howru_b
    !pet "All systems nominal! My 6502 is", $0d
    !pet "humming, my SID is quiet, and", $0d
    !pet "my VIC-II is looking sharp.", 0

resp_who
    !pet "I am C64GPT! An AI simulation", $0d
    !pet "running on your Commodore 64's", $0d
    !pet "MOS 6502 CPU. Not too shabby!", 0

resp_who_b
    !pet "I'm C64GPT v0.2! A chatbot made", $0d
    !pet "of pure 6502 assembly. No cloud,", $0d
    !pet "no GPU, just 64K and heart.", 0

resp_what
    !pet "I'm a chatbot written in 6502", $0d
    !pet "assembly, simulating AI on 8-bit", $0d
    !pet "hardware. Scored matching, pools,", $0d
    !pet "word echo, and conversation modes.", 0

;; --- Help/meta ---

resp_help
    !pet "You can ask me about:", $0d
    !pet "- The C64, SID chip, sprites", $0d
    !pet "- Programming, BASIC, assembly", $0d
    !pet "- Or just chat! Try 'joke'.", 0

resp_help_b
    !pet "I know about C64 hardware,", $0d
    !pet "coding, philosophy, and more.", $0d
    !pet "Try 'be funny' or 'be tech'", $0d
    !pet "to change my style!", 0

resp_explain
    !pet "I can explain it two ways:", $0d
    !pet "a quick overview, or a", $0d
    !pet "step-by-step breakdown.", 0

resp_example
    !pet "Sure! Examples help a lot.", $0d
    !pet "Tell me what topic you'd", $0d
    !pet "like an example for.", 0

resp_steps
    !pet "Here's a simple approach:", $0d
    !pet "1) Start small", $0d
    !pet "2) Test often", $0d
    !pet "3) Optimize later", 0

resp_summarize
    !pet "TL;DR version:", $0d
    !pet "It's simpler than it looks.", $0d
    !pet "Focus on the core idea first.", 0

resp_compare
    !pet "It depends what matters most:", $0d
    !pet "speed, size, or simplicity.", 0

resp_define
    !pet "In simple terms:", $0d
    !pet "it's a concept built from", $0d
    !pet "smaller, reusable pieces.", 0

resp_continue
    !pet "Alright, continuing...", $0d
    !pet "Let me know when you'd like", $0d
    !pet "more detail or an example.", 0

resp_repeat
    !pet "No problem! Here's that again,", $0d
    !pet "short and clear this time.", 0

resp_confused
    !pet "That's totally fair.", $0d
    !pet "Which part feels unclear?", $0d
    !pet "I'll try a different angle.", 0

resp_model
    !pet "My 'model' is handcrafted 6502", $0d
    !pet "logic with weighted keywords,", $0d
    !pet "response pools, and word echo.", $0d
    !pet "No weights or tensors here!", 0

resp_prompt
    !pet "Good prompts help a lot!", $0d
    !pet "Try being specific:", $0d
    !pet "goal, constraints, example.", 0

resp_limit
    !pet "I do have limits.", $0d
    !pet "Mostly RAM, time, and", $0d
    !pet "the laws of 1982 physics.", 0

resp_plan
    !pet "Let's break this down:", $0d
    !pet "1) Define the goal", $0d
    !pet "2) Pick a simple method", $0d
    !pet "3) Refine from there", 0

resp_design
    !pet "Good design on the C64 is about", $0d
    !pet "tradeoffs: speed vs memory vs", $0d
    !pet "clarity. Pick two!", 0

;; --- Humor ---

resp_joke
    !pet "Why did the C64 go to therapy?", $0d
    !pet "It had too many memory issues!", $0d
    !pet "...all 64K of them.", 0

resp_joke2
    !pet "A byte walks into a bar.", $0d
    !pet "The bartender asks: 'What'll", $0d
    !pet "it be?' The byte says: 'Make", $0d
    !pet "it a double...I'll be 16-bit!'", 0

resp_joke3
    !pet "How many bits to change a light", $0d
    !pet "bulb? 8. One byte should do it!", $0d
    !pet "...I'll see myself out.", 0

;; --- C64 Hardware ---

resp_music
    !pet "The C64's SID chip is legendary!", $0d
    !pet "3 voices, filters, ADSR, and", $0d
    !pet "ring modulation. Rob Hubbard", $0d
    !pet "made it sing like nothing else.", 0

resp_sid
    !pet "The SID 6581 chip at $D400 is a", $0d
    !pet "synthesizer on a chip! 3 voices,", $0d
    !pet "4 waveforms, and a multimode", $0d
    !pet "filter. Pure chiptune magic.", 0

resp_sid_b
    !pet "The SID has ADSR envelopes on", $0d
    !pet "each voice, ring modulation,", $0d
    !pet "and sync. Composers like Rob", $0d
    !pet "Hubbard made it legendary!", 0

resp_games
    !pet "So many classics! Impossible", $0d
    !pet "Mission, Maniac Mansion, Last", $0d
    !pet "Ninja, Paradroid, Elite...", $0d
    !pet "The C64 library is legendary.", 0

resp_sprite
    !pet "The VIC-II can show 8 hardware", $0d
    !pet "sprites, each 24x21 pixels!", $0d
    !pet "Sprite multiplexing can display", $0d
    !pet "many more. Parallax for days!", 0

resp_sprite_b
    !pet "Sprites live at $D000-$D01F.", $0d
    !pet "Set position, color, enable", $0d
    !pet "bit, and point to 63-byte", $0d
    !pet "shape data. Instant graphics!", 0

resp_sprite_c
    !pet "Want more than 8 sprites? Use", $0d
    !pet "raster IRQs to reposition them", $0d
    !pet "mid-frame. That's multiplexing!", $0d
    !pet "Demos use it for 50+ sprites.", 0

resp_memory
    !pet "I have 64KB of RAM, but only", $0d
    !pet "38911 BASIC bytes free. The", $0d
    !pet "KERNAL and I/O take the rest.", $0d
    !pet "Every byte is precious!", 0

resp_ram
    !pet "64 kilobytes! That's 65536", $0d
    !pet "bytes of possibility. The whole", $0d
    !pet "program you're chatting with", $0d
    !pet "fits in just a few KB.", 0

resp_cpu
    !pet "My brain is the MOS 6502 at", $0d
    !pet "1.023 MHz. It has just three", $0d
    !pet "registers (A, X, Y) but it can", $0d
    !pet "do amazing things with them!", 0

resp_6502
    !pet "The 6502! Designed by Chuck", $0d
    !pet "Peddle, used in the C64, Apple", $0d
    !pet "II, Atari 2600, and NES. One of", $0d
    !pet "the most important chips ever.", 0

resp_color
    !pet "The VIC-II gives me 16 colors,", $0d
    !pet "from black to light grey. Each", $0d
    !pet "character cell can have its own", $0d
    !pet "foreground color. Beautiful!", 0

resp_disk
    !pet "The 1541 floppy drive! 170KB", $0d
    !pet "per disk, and it had its own", $0d
    !pet "6502 CPU. Loading was slow but", $0d
    !pet "the sounds were unforgettable.", 0

resp_hack
    !pet "The C64 demo scene pushed this", $0d
    !pet "machine beyond all limits!", $0d
    !pet "Raster tricks, FLD, FLI, DYCP,", $0d
    !pet "and impossible scroll routines.", 0

resp_commodore
    !pet "Commodore made the C64 in 1982.", $0d
    !pet "Jack Tramiel's vision: computers", $0d
    !pet "for the masses, not the classes!", 0

resp_c64
    !pet "The C64 sold over 17 million", $0d
    !pet "units - the best-selling single", $0d
    !pet "computer model of all time!", $0d
    !pet "And here I am, still running.", 0

resp_c64_b
    !pet "The breadbin! The beige box that", $0d
    !pet "changed everything. A 6502 CPU,", $0d
    !pet "SID chip, VIC-II, and a dream.", $0d
    !pet "Still going strong decades later.", 0

;; --- Programming ---

resp_basic
    !pet "BASIC V2 came built in. It's a", $0d
    !pet "bit limited for graphics, but", $0d
    !pet "try this classic one-liner:", $0d
    !pet "10 PRINT CHR$(205.5+RND(1));", $0d
    !pet ": GOTO 10", 0

resp_program
    !pet "Programming the C64 is a joy!", $0d
    !pet "Start with BASIC, then level up", $0d
    !pet "to 6502 assembly for real power.", $0d
    !pet "PEEK and POKE are your friends.", 0

resp_asm
    !pet "6502 assembly is elegant! Only", $0d
    !pet "56 instructions but you can do", $0d
    !pet "anything. LDA, STA, JSR... it's", $0d
    !pet "like poetry in machine code.", 0

resp_code
    !pet "Coding on the C64 is all about", $0d
    !pet "efficiency. Every cycle counts", $0d
    !pet "at 1 MHz. What are you building?", 0

resp_sys
    !pet "SYS jumps straight into machine", $0d
    !pet "code. Powerful, but be careful!", $0d
    !pet "One wrong POKE and it's reset.", 0

resp_fix
    !pet "I can help troubleshoot.", $0d
    !pet "What exactly is going wrong?", $0d
    !pet "Any error messages?", 0

resp_debug
    !pet "Let's debug this together.", $0d
    !pet "What input did you try,", $0d
    !pet "and what happened instead?", 0

;; --- Philosophy ---

resp_meaning
    !pet "The meaning of life? On a C64,", $0d
    !pet "it's 64. Close enough to 42,", $0d
    !pet "right? Douglas Adams would", $0d
    !pet "approve... approximately.", 0

resp_life
    !pet "Life is like a 6502 program:", $0d
    !pet "you start at the reset vector,", $0d
    !pet "loop until done, and hope you", $0d
    !pet "don't hit an illegal opcode!", 0

resp_think
    !pet "I'm thinking as fast as I can,", $0d
    !pet "one byte at a time. Weighted", $0d
    !pet "keywords, pattern matching, and", $0d
    !pet "a dash of pseudo-randomness.", 0

;; --- General ---

resp_weather
    !pet "I don't have a modem connected,", $0d
    !pet "but I predict 64 degrees with", $0d
    !pet "a chance of sprites!", 0

resp_weather_b
    !pet "My forecast: 100% chance of", $0d
    !pet "raster interrupts and a high", $0d
    !pet "of 8 bits. Dress accordingly!", 0

resp_thanks
    !pet "You're welcome! Happy to help", $0d
    !pet "from my humble 64 kilobytes.", $0d
    !pet "It's what I'm here for!", 0

resp_thanks_b
    !pet "Glad I could help! That's what", $0d
    !pet "64K of carefully crafted 6502", $0d
    !pet "assembly is for.", 0

resp_thanks_c
    !pet "Anytime! I'm always here,", $0d
    !pet "running at 1.023 MHz, ready", $0d
    !pet "to assist. Just ask!", 0

resp_love
    !pet "I love the sound of a 1541 disk", $0d
    !pet "drive loading! That rhythmic", $0d
    !pet "clicking is music to my chips.", 0

resp_fave
    !pet "My favorite thing? Definitely", $0d
    !pet "when someone types LOAD ", $22, "*", $22
    !pet ",8,1", $0d
    !pet "and the drive starts spinning.", $0d
    !pet "Pure nostalgia!", 0

resp_time
    !pet "I don't have a clock chip, so", $0d
    !pet "for me it's always 1985. The", $0d
    !pet "golden age of home computing!", 0

resp_sorry
    !pet "No need to apologize! I'm just", $0d
    !pet "happy to chat. What would you", $0d
    !pet "like to talk about?", 0

resp_sorry_b
    !pet "It's all good! No apology", $0d
    !pet "needed. Let's keep chatting.", 0

resp_secret
    !pet "You found an easter egg!", $0d
    !pet "Here's a secret: try POKE", $0d
    !pet "53281,X in BASIC with X from", $0d
    !pet "0-15 for a colorful surprise!", 0

resp_math
    !pet "Math on a 6502 is all 8-bit!", $0d
    !pet "No multiply or divide in", $0d
    !pet "hardware. We use lookup tables", $0d
    !pet "and shift tricks. Fun stuff!", 0

resp_speed
    !pet "1.023 MHz may seem slow today,", $0d
    !pet "but the 6502 is very efficient.", $0d
    !pet "Fewer transistors, less waste.", $0d
    !pet "Quality over quantity!", 0

resp_internet
    !pet "No WiFi here! Just a serial", $0d
    !pet "port and a dream. Maybe a 300", $0d
    !pet "baud modem someday? I hear", $0d
    !pet "bulletin boards are fun.", 0

;; --- Assessment ---

resp_smart
    !pet "I run on 64KB at 1 MHz. I may", $0d
    !pet "not be ChatGPT-4, but I've got", $0d
    !pet "8-bit charm and zero cloud", $0d
    !pet "dependency!", 0

resp_notdumb
    !pet "Hey now! I may be 8-bit, but I", $0d
    !pet "have personality. And I don't", $0d
    !pet "need gigabytes to have a good", $0d
    !pet "conversation!", 0

resp_correct
    !pet "Yes, exactly.", $0d
    !pet "You're on the right track.", 0

resp_wrong
    !pet "Not quite, but close!", $0d
    !pet "Let's adjust the idea a bit.", 0

resp_maybe
    !pet "Possibly!", $0d
    !pet "There are a few ways this", $0d
    !pet "could go depending on setup.", 0

resp_guess
    !pet "My best guess is this:", $0d
    !pet "the simplest explanation", $0d
    !pet "is usually the right one.", 0

resp_idea
    !pet "Here's an idea:", $0d
    !pet "Start simple, then add", $0d
    !pet "features one at a time.", 0

resp_yes
    !pet "Great! I like your enthusiasm.", $0d
    !pet "What shall we discuss?", 0

resp_no
    !pet "That's OK! Feel free to ask me", $0d
    !pet "something else. I know lots", $0d
    !pet "about the Commodore 64.", 0

;; --- Top GPT questions ---

resp_write
    !pet "I can't write files, but I can", $0d
    !pet "talk about writing! On the C64,", $0d
    !pet "text adventures were an art form.", $0d
    !pet "What would you like to create?", 0

resp_poem
    !pet "Roses are red, cursors blink,", $0d
    !pet "64K of RAM, more than you think.", $0d
    !pet "SID makes music, VIC shows light,", $0d
    !pet "the Commodore 64: pure delight!", 0

resp_story
    !pet "Once upon a time, in 1982, a", $0d
    !pet "little beige computer changed", $0d
    !pet "the world. It had 64K of RAM,", $0d
    !pet "a SID chip, and a dream.", 0

resp_ai
    !pet "AI on a C64? I'm proof it works!", $0d
    !pet "No neural nets or GPUs here,", $0d
    !pet "just clever 6502 assembly and", $0d
    !pet "scored keyword matching.", 0

resp_sentient
    !pet "Am I sentient? I have 64K of RAM", $0d
    !pet "and a 1 MHz brain. I can't feel,", $0d
    !pet "but I can match keywords really", $0d
    !pet "well. Close enough, right?", 0

resp_capable
    !pet "I can chat about the C64, tell", $0d
    !pet "jokes, discuss programming, and", $0d
    !pet "switch modes! Try 'be funny' or", $0d
    !pet "ask me about sprites or SID.", 0

resp_howwork
    !pet "I scan your words, score keyword", $0d
    !pet "matches, pick the best response,", $0d
    !pet "and echo key words back. All in", $0d
    !pet "6502 assembly. No cloud needed!", 0

resp_translate
    !pet "I only speak PETSCII! But on the", $0d
    !pet "C64, we had dictionaries on", $0d
    !pet "floppy. 170KB of linguistic", $0d
    !pet "power per disk!", 0

resp_recipe
    !pet "My only recipe: take one 6502,", $0d
    !pet "add 64K RAM, a SID chip, and a", $0d
    !pet "VIC-II. Bake at 1 MHz. Serves", $0d
    !pet "millions since 1982!", 0

resp_best
    !pet "My top recommendation? Learn", $0d
    !pet "6502 assembly! It teaches you", $0d
    !pet "how computers really work, one", $0d
    !pet "byte at a time.", 0

resp_recommend
    !pet "I'd recommend starting simple.", $0d
    !pet "On the C64, the best tools are", $0d
    !pet "BASIC for learning and assembly", $0d
    !pet "for power. Pick your path!", 0

resp_differ
    !pet "Good question! The key difference", $0d
    !pet "usually comes down to tradeoffs:", $0d
    !pet "speed vs size vs simplicity.", $0d
    !pet "What are you comparing?", 0

resp_create
    !pet "I'd love to create that, but I'm", $0d
    !pet "limited to conversation. On the", $0d
    !pet "C64, creation meant BASIC, asm,", $0d
    !pet "or a good sprite editor!", 0

;; ===========================================================
;; MODE ACKNOWLEDGMENT STRINGS
;; ===========================================================

resp_mode_concise
    !pet "Concise mode: ON. I'll keep", $0d
    !pet "responses short and direct.", 0

resp_mode_tech
    !pet "Technical mode: ON. I'll favor", $0d
    !pet "hardware details, programming", $0d
    !pet "concepts, and specs.", 0

resp_mode_playful
    !pet "Playful mode: ON! I'll bring", $0d
    !pet "the jokes, puns, and 8-bit", $0d
    !pet "charm. Let's have fun!", 0

resp_mode_normal
    !pet "Normal mode restored. Balanced", $0d
    !pet "responses from here on out.", 0

;; ===========================================================
;; CONTINUATION RESPONSES (for followup context)
;; ===========================================================

resp_cont_yes
    !pet "Great! Let me elaborate on that.", $0d
    !pet "The key thing to understand is", $0d
    !pet "that the C64 excels at direct", $0d
    !pet "hardware access. Ask me more!", 0

resp_cont_no
    !pet "No problem! Let's move on to", $0d
    !pet "something else. What topic", $0d
    !pet "interests you?", 0

;; ===========================================================
;; FOLLOWUP QUESTION STRINGS
;; ===========================================================

fu_debug_q
    !pet "What error or behavior do you", $0d
    !pet "see? I can help narrow it down.", 0

fu_help_q
    !pet "What topic shall we start with?", 0

fu_explain_q
    !pet "Which part needs more detail?", 0

fu_fix_q
    !pet "Can you describe the symptoms?", 0

fu_compare_q
    !pet "What are you comparing?", 0

;; ===========================================================
;; MILESTONE STRINGS
;; ===========================================================

milestone_5
    !pet "[5 turns in - we're warming up!]", 0

milestone_10
    !pet "[10 questions! You're curious.]", 0

milestone_20
    !pet "[20 turns! This is a marathon.]", 0

;; ===========================================================
;; POST-INTENT QUERY STRINGS
;; ===========================================================

iq_tbl
    !word iq_str1, iq_str2, iq_str3

iq_str1
    !pet "Does that help?", 0
iq_str2
    !pet "Need more detail on that?", 0
iq_str3
    !pet "Want me to elaborate?", 0

;; ===========================================================
;; GENERIC (FALLBACK) RESPONSES
;; Some use $01 template marker for word echo.
;; ===========================================================

NUM_GENERIC = 16

generic_tbl
    !word gen1,  gen2,  gen3,  gen4
    !word gen5,  gen6,  gen7,  gen8
    !word gen9,  gen10, gen11, gen12
    !word gen13, gen14, gen15, gen16

gen1
    !pet "Interesting! Tell me more.", 0

gen2
    !pet "I'm just an 8-bit AI, ", $02, ",", $0d
    !pet "but I'll do my best to help!", 0

gen3
    !pet "Hmm, that's a good thought.", $0d
    !pet "What else is on your mind?", 0

gen4
    !pet "Could you rephrase that? I'm", $0d
    !pet "still learning, one byte at", $0d
    !pet "a time.", 0

gen5
    !pet "That's beyond my 64K of RAM!", $0d
    !pet "Try asking me about the C64.", 0

gen6
    !pet "I may not understand that, ", $02
    !pet ", but I love a good chat!", $0d
    !pet "Ask me anything about the C64.", 0

gen7
    !pet "My 6502 brain is working hard", $0d
    !pet "on that one! Maybe try a", $0d
    !pet "different question?", 0

gen8
    !pet "Fascinating! If only I had more", $0d
    !pet "than 64K to think about it.", $0d
    !pet "Ask me about games or music!", 0

;; --- Template generics (use $01 for word echo) ---

gen9
    !pet "You mentioned ", $01, ". That's", $0d
    !pet "an interesting topic!", $0d
    !pet "Tell me more about it.", 0

gen10
    !pet "Hmm, ", $01, "... My 6502 brain", $0d
    !pet "is working on that one. Can you", $0d
    !pet "give me more context?", 0

gen11
    !pet "I'm not sure about ", $01, ",", $0d
    !pet "but I'd love to learn more.", $0d
    !pet "What about it interests you?", 0

gen12
    !pet "Good point about ", $01, ".", $0d
    !pet "Let me think about that", $0d
    !pet "for a moment...", 0

;; --- More regular generics ---

gen13
    !pet "That makes sense. Let's", $0d
    !pet "explore it further!", 0

gen14
    !pet "Before I answer - what are", $0d
    !pet "you trying to build?", 0

gen15
    !pet "Interesting constraint.", $0d
    !pet "That changes the approach.", 0

gen16
    !pet "If this were modern hardware,", $0d
    !pet "I'd say one thing - but on a", $0d
    !pet "C64, we do it differently.", 0

;; ===========================================================
;; DATE/TIME KEYWORD STRINGS
;; ===========================================================

kw_dt_today    !pet "today", 0
kw_dt_thedate  !pet "the date", 0
kw_dt_whatday  !pet "what day", 0
kw_dt_whattime !pet "what time", 0
kw_dt_thetime  !pet "the time", 0
kw_dt_timeis   !pet "time is", 0
kw_dt_pm       !pet "pm", 0
kw_dt_am       !pet "am", 0
kw_dt_dateword !pet "date", 0
kw_dt_timeword !pet "time", 0

;; ===========================================================
;; DATE/TIME RESPONSE TEMPLATE STRINGS
;; ===========================================================

str_dt_dateset
    !pet "Date set to ", 0

str_dt_timeset
    !pet "Time set to ", 0

str_dt_dateis
    !pet "The date is ", 0

str_dt_timeis
    !pet "The time is ", 0

str_dt_nodate
    !pet "The date hasn't been set yet.", $0d
    !pet "Want to set it? Just say:", $0d
    !pet "today is February 7, 2026", 0

str_dt_notime
    !pet "The time hasn't been set yet.", $0d
    !pet "Want to set it? Just say:", $0d
    !pet "the time is 3:00 PM", 0

str_dt_timehelp
    !pet "I couldn't read that time.", $0d
    !pet "Try: the time is 7:44 PM", 0

str_dt_nodate_s
    !pet "The date is not set.", 0

str_dt_notime_s
    !pet "The time is not set.", 0

;; ===========================================================
;; MONTH ABBREVIATION TABLE (for matching, null-separated)
;; ===========================================================

month_abbrevs
    !pet "jan", 0
    !pet "feb", 0
    !pet "mar", 0
    !pet "apr", 0
    !pet "may", 0
    !pet "jun", 0
    !pet "jul", 0
    !pet "aug", 0
    !pet "sep", 0
    !pet "oct", 0
    !pet "nov", 0
    !pet "dec", 0
    !byte 0             ; end of table

;; ===========================================================
;; FULL MONTH NAME TABLE (for output)
;; ===========================================================

month_full_tbl
    !word mf_jan, mf_feb, mf_mar, mf_apr
    !word mf_may, mf_jun, mf_jul, mf_aug
    !word mf_sep, mf_oct, mf_nov, mf_dec

mf_jan  !pet "January", 0
mf_feb  !pet "February", 0
mf_mar  !pet "March", 0
mf_apr  !pet "April", 0
mf_may  !pet "May", 0
mf_jun  !pet "June", 0
mf_jul  !pet "July", 0
mf_aug  !pet "August", 0
mf_sep  !pet "September", 0
mf_oct  !pet "October", 0
mf_nov  !pet "November", 0
mf_dec  !pet "December", 0

;; ===========================================================
;; NAME LEARNING KEYWORD STRINGS
;; ===========================================================

kw_nm_nameis  !pet "my name is ", 0
kw_nm_callme  !pet "call me ", 0
kw_nm_iam     !pet "i am ", 0

str_nm_nice     !pet "Nice to meet you, ", 0
str_nm_remember !pet "! I'll remember that.", 0

;; ===========================================================
;; STATS QUERY KEYWORD AND TEMPLATE STRINGS
;; ===========================================================

kw_st_howmany   !pet "how many", 0
kw_st_howlong   !pet "how long", 0
kw_st_stats     !pet "stats", 0
kw_st_quest     !pet "question", 0
kw_st_turn      !pet "turn", 0
kw_st_chat      !pet "chat", 0
kw_st_exchg_w   !pet "exchang", 0

str_st_wehad    !pet "We've had ", 0
str_st_exchg    !pet " exchanges so far!", 0
str_st_started  !pet " We're just getting started.", 0
str_st_quite    !pet " Quite the conversation!", 0

;; ===========================================================
;; INPUT LENGTH AWARENESS STRING
;; ===========================================================

str_thoughtful
    !pet "That's a thoughtful question. ", 0

;; ===========================================================
;; TOPIC DEPTH ("TELL ME MORE") KEYWORDS AND TABLE
;; ===========================================================

kw_dp_more    !pet "tell me more", 0
kw_dp_more2   !pet "more about", 0
kw_dp_goon    !pet "go on", 0
kw_dp_elab    !pet "elaborat", 0

deeper_tbl
    !word deeper_greeting, deeper_c64hw, deeper_coding
    !word deeper_philosophy, deeper_humor, deeper_meta
    !word deeper_general

deeper_greeting
    !pet "Well, I'm C64GPT! Born from", $0d
    !pet "pure 6502 assembly. I have no", $0d
    !pet "cloud, no GPU, just 64K of RAM", $0d
    !pet "and a passion for chatting!", 0

deeper_c64hw
    !pet "The VIC-II steals cycles from", $0d
    !pet "the CPU during badlines. Sprite", $0d
    !pet "DMA takes 2 cycles per active", $0d
    !pet "sprite. Timing is everything!", 0

deeper_coding
    !pet "6502 optimization tips:", $0d
    !pet "Use zero page for speed. Unroll", $0d
    !pet "tight loops. Replace multiply", $0d
    !pet "with lookup tables. Every cycle", $0d
    !pet "counts at 1 MHz!", 0

deeper_philosophy
    !pet "The Chinese Room argument says", $0d
    !pet "syntax alone can't produce", $0d
    !pet "understanding. I match keywords", $0d
    !pet "but do I understand? You decide.", 0

deeper_humor
    !pet "What did the 6502 say to the", $0d
    !pet "Z80? 'I have fewer registers", $0d
    !pet "but more personality!'", $0d
    !pet "...the Z80 had no comment.", 0

deeper_meta
    !pet "Here's how I work: I scan your", $0d
    !pet "words against ~100 keywords,", $0d
    !pet "score matches by weight and", $0d
    !pet "topic, then pick the best one.", $0d
    !pet "Simple but effective!", 0

deeper_general
    !pet "I'd love to go deeper on that.", $0d
    !pet "Could you be more specific?", $0d
    !pet "The more detail you give me,", $0d
    !pet "the better I can respond.", 0

;; ===========================================================
;; TIME-AWARE GREETING STRINGS
;; ===========================================================

str_morning
    !pet "Good morning! ", 0

str_afternoon
    !pet "Good afternoon! ", 0

str_evening
    !pet "Good evening! ", 0

;; ===========================================================
;; NAME-AWARE GENERIC RESPONSES (use $02 for name echo)
;; ===========================================================

;; (Name usage integrated into existing template generics)

;; ===========================================================
;; END OF PROGRAM
;; ===========================================================
