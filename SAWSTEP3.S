;
; sawbench step sequencer, for atari st, by pieter van der meer, 2015
;

ENABLE_INTERRUPTS:	=	1

sawbench:

; set supervisor mode
	pea	stack
	move.w	#$20,-(sp)
	trap	#1

	pea	bootmsg
	move.w	#9,-(sp)
	trap	#1
	addq	#6,sp

	ifne	ENABLE_INTERRUPTS

	move.l	$0070.w,oldvbl
	move.l	$0114.w,old200hz

;	move.l	#new200hz,$0114.w
	move.l	#newvbl,$0070.w

	endc

	bsr	init

	bsr	init_dummy_sequence

mainloop:
; check if there is keyboard data
	move.w	#$b,-(sp)
	trap	#1
	addq	#2,sp
	tst.w	d0
	beq	nokey

; read keyboard data
	move.w	#7,-(sp)
	trap	#1
	addq	#2,sp

	bsr	handle_gemdos_keys
	
nokey:	
	tst.w	exit_engaged
	bne	exit

	bsr	print_sequence

	bra	mainloop

exit:

	ifne	ENABLE_INTERRUPTS

; restore system variables
	move.l	oldvbl,$0070.w
	move.l	old200hz,$0114.w

	endc

; kick the bucket
	clr.w	-(sp)
	trap	#1
	addq	#2,sp

;-------------------------------------------------------------------------------

; initialize defaults, clear buffers, etc
init:
; set up default midi channel
	move.w	#0,channel

; set midi channel in cc packets
	move.b	channel,d0
	or.b	d0,glide_packet

; reset sequencer tempo, position, effects
	move.w	#50,numticks
	moveq	#0,d0
	move.w	d0,position
	move.w	d0,next_position
	move.w	d0,playing
	move.w	d0,fm_pending
	move.w	d0,glide_pending
	move.w	d0,adsrloopmask_pending
	move.b	d0,adsrloopmask_packet+2

; reset program state
	clr.w	exit_engaged

; prepare gui
	bsr	precalc_velocity2text
	bsr	copy_logo
	rts

copy_logo:
	move.w	#2,-(sp)
	trap	#14
	addq	#2,sp
	move.l	d0,vbase
	lea	degas+34,a1
	movea.l	vbase,a0
	adda.l	#80*(400-131),a0
	move.w	#131-1,d7
.loop:
	rept	20
	move.l	(a1)+,(a0)+
	endr
	dbf	d7,.loop
	rts

vbase:	ds.l	1

init_dummy_sequence:
; midi note on sequence
	lea	pattern,a0
	moveq	#16-1,d7
	moveq	#2*12,d1
.loop:	move.b	#%10010000,d0
	or.b	channel,d0
	move.b	d0,(a0)+			; header
	move.b	d1,(a0)+			; key
	move.b	#127,(a0)+			; velocity
	addq.b	#1,d1
	dbf	d7,.loop
	rts

precalc_velocity2text:
	lea	velocity2text,a0
	moveq	#0,d7

.loop:	moveq	#0,d0
	move.b	d7,d0
	move.w	d0,d1
	divu.w	#10,d0
	move.l	d0,d2
	swap	d2				; d2.b=lower decimal
	andi.l	#$0000FFFF,d0
	divu.w	#10,d0				; d0.b=upper decimal
	move.l	d0,d1
	swap	d1				; d1.b=middle decimal
	addi.b	#"0",d0
	addi.b	#"0",d1
	addi.b	#"0",d2
	move.b	d0,(a0)+
	move.b	d1,(a0)+
	move.b	d2,(a0)+
	move.b	#" ",(a0)+
	addq.w	#1,d7
	cmpi.w	#128,d7
	blt.s	.loop
	rts

; handle keyboard input 
handle_gemdos_keys:
	cmpi.b	#27,d0				; escape
	bne.s	.not_exit
	st	exit_engaged
	bra	.end
.not_exit:

	cmpi.b	#" ",d0				; space
	bne.s	.not_space
	not.w	playing
	bra	.end
.not_space:

	move.l	d0,d1
	swap	d1

	cmpi.b	#$4B,d1				; left arrow
	bne.s	.not_left
	subq.w	#1,position
	andi.w	#15,position
	bra	.end
.not_left:

	cmpi.b	#$4D,d1				; right arrow
	bne.s	.not_right
	addq.w	#1,position
	andi.w	#15,position
	bra	.end
.not_right:

	cmpi.b	#$48,d1				; up arrow
	bne.s	.not_up
	lea	pattern,a0
	move.w	position,d1
	mulu.w	#3,d1
	adda.w	d1,a0
	addq.b	#1,1(a0)			; modify key
	andi.b	#127,1(a0)
	bra	.end
.not_up:

	cmpi.b	#$50,d1				; down arrow
	bne.s	.not_down
	lea	pattern,a0
	move.w	position,d1
	mulu.w	#3,d1
	adda.w	d1,a0
	subq.b	#1,1(a0)			; modify key
	andi.b	#127,1(a0)
	bra	.end
.not_down:

	cmpi.b	#$33,d1				; ,
	bne.s	.not_comma
	lea	pattern,a0
	move.w	position,d1
	mulu.w	#3,d1
	adda.w	d1,a0
	subq.b	#4,2(a0)			; modify velocity
	bpl	.end
	move.b	#0,2(a0)
	bra	.end
.not_comma:

	cmpi.b	#$34,d1				; .
	bne.s	.not_dot
	lea	pattern,a0
	move.w	position,d1
	mulu.w	#3,d1
	adda.w	d1,a0
	addq.b	#4,2(a0)			; modify velocity
	bpl	.end
	move.b	#127,2(a0)
	bra	.end
.not_dot:

	cmpi.b	#$4E,d1				; keypad -
	bne.s	.check_minus
	subq.w	#1,numticks
	cmpi.w	#MIN_NUMTICKS,numticks
	bgt	.end
	move.w	#MIN_NUMTICKS,numticks
	bra	.end
.check_minus:
	cmpi.b	#$4A,d1				; keypad +
	bne.s	.not_plus
	addq.w	#1,numticks
	cmpi.w	#MAX_NUMTICKS,numticks
	blt	.end
	move.w	#MAX_NUMTICKS,numticks
.not_plus:

; glide	
	cmpi.b	#"g",d0
	bne.s	.not_g
	st	glide_pending
	lea	glide_packet+2,a0
	addq.b	#1,(a0)
	bpl.s	.not_g
	move.b	#127,(a0)
.not_g:

	cmpi.b	#"G",d0
	bne.s	.not_G
	st	glide_pending
	lea	glide_packet+2,a0
	subq.b	#1,(a0)
	bgt.s	.not_G
	move.b	#1,(a0)
.not_G:

; FM
	cmpi.b	#"F",d0
	bne.s	.not_F
	st	fm_pending
	lea	fm_packet+2,a0
	addq.b	#1,(a0)
	bpl.s	.not_F
	move.b	#127,(a0)
.not_F:

	cmpi.b	#"f",d0
	bne.s	.not_f
	st	fm_pending
	lea	fm_packet+2,a0
	subq.b	#1,(a0)
	bpl.s	.not_f
	move.b	#0,(a0)
.not_f:

	cmpi.b	#"[",d0
	bne.s	.not_lbracket
	st	adsrloopmask_pending
	lea	adsrloopmask_packet+2,a0
	bchg	#0,(a0)
.not_lbracket:

	cmpi.b	#"]",d0
	bne.s	.not_rbracket
	st	adsrloopmask_pending
	lea	adsrloopmask_packet+2,a0
	bchg	#1,(a0)
.not_rbracket:

	cmpi.b	#"T",d0
	bne.s	.not_T
	st	keytrack_pending
	lea	keytrack_packet+2,a0
	addq.b	#1,(a0)
	bpl.s	.not_T
	move.b	#127,(a0)
.not_T:

	cmpi.b	#"t",d0
	bne.s	.not_t
	st	keytrack_pending
	lea	keytrack_packet+2,a0
	subq.b	#1,(a0)
	bpl.s	.not_t
	move.b	#0,(a0)
.not_t:

	cmpi.b	#"l",d0
	bne.s	.not_l
	st	legato_pending
	not.b	legato_packet+2
	andi.b	#1,legato_packet+2
.not_l:

	cmpi.b	#"0",d0
	bne.s	.not_0
	lea	pattern,a0
	move.w	position,d2
	mulu.w	#3,d2
	adda.w	d2,a0
	move.b	#0,2(a0)		; zero velocity!
.not_0:
	

.end:
	rts

; print sequence as gemdos string
print_sequence:
; first row: notes and octaves
	lea	pattern_text,a0
	lea	note2text,a1
	lea	pattern,a2
	moveq	#16-1,d7
	move.w	d7,d6
	sub.w	position,d6

.loop:	moveq	#0,d0
	move.b	1(a2),d0			; d0.l=midi key
	divu.w	#12,d0
	move.w	d0,d1				; d1.w=quotient (octave)
	swap	d0				; d0.w=remainder (note)
	addi.w	#"0",d1				; d1.b=octave nr (ASCII numeral)
	add.w	d0,d0				; d0.w=index into note2text table
	cmp.b	d6,d7
	bne.s	.non_inverted
	move.b	#27,(a0)+
	move.b	#"p",(a0)+
.non_inverted:
	move.b	(a1,d0.w),(a0)+			; copy note text
	move.b	1(a1,d0.w),(a0)+		; copy note text
	move.b	d1,(a0)+			; copy octave text
	move.b	#" ",(a0)+			; space
	cmp.b	d6,d7
	bne.s	.non_inverted2
	move.b	#27,(a0)+
	move.b	#"q",(a0)+
.non_inverted2:
	addq	#3,a2				; a2: next midi packet
	dbf	d7,.loop

	move.b	#$A,(a0)+
	move.b	#$D,(a0)+

; second row: velocities
	lea	velocity2text,a1
	lea	pattern,a2
	moveq	#16-1,d7

.loop2:	moveq	#0,d0
	move.b	2(a2),d0
	lsl.w	#2,d0
	lea	(a1,d0.w),a3
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	addq	#3,a2				; a2: next midi packet
	dbf	d7,.loop2

	move.b	#$A,(a0)+
	move.b	#$D,(a0)+

	moveq	#0,d0
	move.b	glide_packet+2,d0
	move.b	#"G",(a0)+
	move.b	#" ",(a0)+
	lsl.w	#2,d0
	lea	(a1,d0.w),a3
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+

	moveq	#0,d0
	move.b	fm_packet+2,d0
	move.b	#"F",(a0)+
	move.b	#" ",(a0)+
	lsl.w	#2,d0
	lea	(a1,d0.w),a3
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+

	moveq	#0,d0
	move.b	keytrack_packet+2,d0
	move.b	#"T",(a0)+
	move.b	#" ",(a0)+
	lsl.w	#2,d0
	lea	(a1,d0.w),a3
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+
	move.b	(a3)+,(a0)+

	btst	#0,adsrloopmask_packet+2
	beq.s	.la_color
	move.b	#27,(a0)+
	move.b	#"p",(a0)+
.la_color:
	move.b	#"l",(a0)+
	move.b	#"a",(a0)+
	btst	#0,adsrloopmask_packet+2
	beq.s	.la_color2
	move.b	#27,(a0)+
	move.b	#"q",(a0)+
.la_color2:

	move.b	#" ",(a0)+

	btst	#1,adsrloopmask_packet+2
	beq.s	.lf_color
	move.b	#27,(a0)+
	move.b	#"p",(a0)+
.lf_color:
	move.b	#"l",(a0)+
	move.b	#"f",(a0)+
	btst	#1,adsrloopmask_packet+2
	beq.s	.lf_color2
	move.b	#27,(a0)+
	move.b	#"q",(a0)+
.lf_color2:

	move.b	#" ",(a0)+

	tst.b	legato_packet+2
	beq.s	.leg_color
	move.b	#27,(a0)+
	move.b	#"p",(a0)+
.leg_color:
	move.b	#"L",(a0)+
	tst.b	legato_packet+2
	beq.s	.leg_color2
	move.b	#27,(a0)+
	move.b	#"q",(a0)+
.leg_color2:

	move.b	#" ",(a0)+

	move.b	#27,(a0)+
	move.b	#"A",(a0)+

	move.b	#27,(a0)+
	move.b	#"A",(a0)+

	move.b	#$D,(a0)+
	move.b	#0,(a0)+

; print it
	pea	pattern_text
	move.w	#9,-(sp)
	trap	#1
	addq	#6,sp
	
	rts

; a0: buffer
; d7.w=nr of bytes -1
send_midi:
.loop:	move.b	$FFFFFC04.w,d0
	andi.b	#2,d0
	beq.s	.loop
	move.b	(a0)+,$FFFFFC06.w
	dbf	d7,.loop
	rts

;-------------------------------------------------------------------------------

MIN_NUMTICKS:=	10
MAX_NUMTICKS:=	400

new200hz:
	move.l	old200hz,-(sp)
	rts

newvbl:	tst.w	playing
	beq	.done_playing

	movem.l	d0-a6,-(sp)

; wait set nr of 200 Hz clockticks till next position
	move.w	$04BC.w,d2
	move.w	d2,d1
	sub.w	old4bc,d1
	cmp.w	numticks,d1			; 200 Hz ticks
	blo	.note_done
	move.w	d2,old4bc

; hard pokes into midi acia, seeing that midiws() doesn't work in interrupt.

	move.w	next_position,position

	lea	pattern,a0
	move.w	position,d0
	mulu.w	#3,d0
	adda.w	d0,a0
	moveq	#3-1,d7
	bsr.s	send_midi

	tst.w	glide_pending
	beq.s	.glide_done
	lea	glide_packet,a0
	moveq	#3-1,d7
	bsr.s	send_midi
	clr.w	glide_pending
.glide_done:

	tst.w	fm_pending
	beq.s	.fm_done
	lea	fm_packet,a0
	moveq	#3-1,d7
	bsr	send_midi
	clr.w	fm_pending
.fm_done:

	tst.w	adsrloopmask_pending
	beq.s	.adsrloopmask_done
	lea	adsrloopmask_packet,a0
	moveq	#3-1,d7
	bsr	send_midi
	clr.w	adsrloopmask_pending
.adsrloopmask_done:

	tst.w	keytrack_pending
	beq.s	.keytrack_done
	lea	keytrack_packet,a0
	moveq	#3-1,d7
	bsr	send_midi
	clr.w	keytrack_pending
.keytrack_done:

	tst.w	legato_pending
	beq.s	.legato_done
	lea	legato_packet,a0
	moveq	#3-1,d7
	bsr	send_midi
	clr.w	legato_pending
.legato_done:

; increase position
	addq.w	#1,next_position
	andi.w	#15,next_position

.note_done:

	movem.l	(sp)+,d0-a6

.done_playing:

	addq.l	#1,$0466.w

	rte

	ifne	0

newvbl:	;movem.l	d0-a6,-(sp)

	addq.l	#1,$0466.w			; increase system vbl count

	;movem.l	(sp)+,d0-a6
	rte

	endc

;-------------------------------------------------------------------------------

	data

bootmsg:dc.b	27,"E"				; clear screen
	dc.b	"Sawbench Step Sequencer, Tasty Chips Electronics 2015",$A,$D,0

fm_packet:
	dc.b	%10110000,$01,0
keytrack_packet:
	dc.b	%10110000,$59,64
glide_packet:
	dc.b	%10110000,$5B,127
legato_packet:
	dc.b	%10110000,$5C,0
adsrloopmask_packet:
	dc.b	%10110000,$5D,0

	even

note2text:
	dc.b	"C-"
	dc.b	"C#"
	dc.b	"D-"
	dc.b	"D#"
	dc.b	"E-"
	dc.b	"F-"
	dc.b	"F#"
	dc.b	"G-"
	dc.b	"G#"
	dc.b	"A-"
	dc.b	"A#"
	dc.b	"B-"

degas:	incbin	sawbench.pi3

	even

;-------------------------------------------------------------------------------

	bss

	ds.l	1024
stack:	

old4bc:	ds.w	1
key_time:
	ds.w	1
oldvbl:	ds.l	1
old200hz:
	ds.l	1

exit_engaged:
	ds.w	1
playing:ds.w	1
glide_pending:
	ds.w	1
fm_pending:
	ds.w	1
adsrloopmask_pending:
	ds.w	1
keytrack_pending:
	ds.w	1
legato_pending:
	ds.w	1

numticks:
	ds.w	1
next_position:
	ds.w	1
position:
	ds.w	1
channel:ds.w	1
pattern:ds.b	3*16			; header, note, velocity

velocity2text:
	ds.b	128*4

pattern_text:
	ds.b	256
