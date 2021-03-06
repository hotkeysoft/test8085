.module 	testio
.title 		Test IO

STACK		=	0xFFFF		;SYSTEM STACK

KBD		=	0x00		;KEYBOARD PORT BASE

LCD		=	0x20		;LCD OUTPUT PORT BASE
LCDC	=	LCD+0		;LCD CTRL PORT
LCDD	= LCD+1		;LCD DATA PORT

UART	=	0x60			;UART PORT BASE
U_RBR	=	UART+0			;RECEIVER BUFFER REGISTER (READ ONLY)
U_THR	=	UART+0			;TRANSMITTER HOLDING REGISTER (WRITE ONLY)
U_IER	=	UART+1			;INTERRUPT ENABLE REGISTER
U_IIR	=	UART+2			;INTERRUPT IDENTIFICATION REGISTER (READ ONLY)
U_LCR	=	UART+3			;LINE CONTROL REGISTER
U_MCR	=	UART+4			;MODEM CONTROL REGISTER
U_LSR	=	UART+5			;LINE STATUS REGISTER
U_MSR	=	UART+6			;MODEM STATUS REGISTER
U_SCR	=	UART+7			;SCRATCH REGISTER
U_DLL	=	UART+0			;DIVISOR LATCH (LSB)
U_DLM	= UART+1			;DIVISOR LATCH (MSB) 


TIMER	=	0x40			;TIMER PORT BASE
T_C0	=	TIMER+0			;COUNTER 0
T_C1	=	TIMER+1			;COUNTER 1
T_C2	=	TIMER+2			;COUNTER 2
T_CWR	=	TIMER+3			;CONTROL WORD REGISTER


;MISC	= 0x80; MISC PORT BASE

.area	BOOT	(ABS)

;*********************************************************
.org	0x0024
RST45: ; TRAP INTERRUPT
	DI
	JMP	INTTI0

;*********************************************************
.org	0x0034
RST65:
	DI
	JMP	INTUART
	
;*********************************************************
.org	0x003C
RST75:
	DI
	JMP	INTTI0


.org 	0x0000

RST0:
	DI
	LXI	SP,STACK	;INITALIZE STACK
	JMP START
	
;*********************************************************
;* MAIN PROGRAM
;*********************************************************
.area 	_CODE

START:
	CALL IO_INITTIMER
	CALL	IO_INITUART	;INITIALIZE UART	
	CALL IO_SOUNDOFF ;
	CALL	IO_INITKBBUF	;INITIALIZE KEYBOARD BUFFER

	MVI	A,8		;SET INTERRUPT MASK
	SIM
	EI			;ENABLE INTERRUPTS

	CALL IO_BEEP

	MVI	A, 'R
	CALL	IO_PUTC ; SEND TO UART
	MVI	A, 'E
	CALL	IO_PUTC ; SEND TO UART
	MVI	A, 'A
	CALL	IO_PUTC ; SEND TO UART
	MVI	A, 'D
	CALL IO_PUTC ; SEND TO UART
	MVI	A, 'Y
	CALL	IO_PUTC ; SEND TO UART
	MVI	A, 10
	CALL	IO_PUTC ; SEND TO UART
	MVI	A, 13
	CALL	IO_PUTC ; SEND TO UART


LOOP:
	CALL WAITFORCHAR
	CALL IO_PUTC
	
	JMP LOOP

;*********************************************************
;* TIMER ROUTINES
;*********************************************************

;* IO_BEEP:  MAKES A 440HZ BEEP FOR 1/2 SECOND
IO_BEEP::
	PUSH 	PSW
	
	MVI	A,45			;LA4 440HZ
	CALL	IO_SOUNDON
	MVI	A,5		
	CALL 	IO_DELAY		;WAIT 5 * 100 MS
	CALL	IO_SOUNDOFF
	
	POP	PSW
	RET
	
;*********************************************************
;* IO_SOUNDON:  PROGRAMS COUNTER 0 AND ENABLES SOUND OUTPUT
IO_SOUNDON::
	PUSH 	PSW
	PUSH	B
	
	CALL	IO_SOUNDOFF		;TURNS OFF SOUND BEFORE REPROGRAMMING
	
	RLC				;OFFSET *= 2 (TABLE CONTAINS WORDS)

	MVI	B,0
	MOV	C,A			;OFFSET IN B-C
	
	LXI	H,NOTES			;TABLE BASE IN H-L
	DAD	B			;ADD OFFSET TO H-L
	
	MOV	A,M			;BYTE AT H-L IN A (NOTE LSB)
	
	OUT	T_C2			;DIVIDER LSB TO COUNTER
	
	INX	H			;H-L POINTS TO NEXT BYTE
	MOV	A,M			;BYTE AD H-L IN A (NOTE MSB)
	
	OUT	T_C2			;DIVIDER MSB TO COUNTER	
	
	IN	U_MCR			;INPUT MISC REGISTER
	ORI	0x04			;TURNS ON BIT 2
	OUT	U_MCR			;OUTPUT MISC REGISTER
	
	POP	B
	POP	PSW	
	RET

;*********************************************************
;* IO_SOUNDOFF:  DISABLES SOUND OUTPUT
IO_SOUNDOFF::
	PUSH 	PSW
	
	IN	U_MCR			;INPUT MISC REGISTER
	ANI	0xFB			;TURNS OFF BIT 2
	OUT	U_MCR			;OUTPUT MISC REGISTER
	
	POP	PSW
	RET	

;*********************************************************
;* IO_INITTIMER:  INITIALIZES TIMERS
IO_INITTIMER::
	LXI	H,0x0000		;CLEAR H-L
	SHLD	TICNT			;H-L IN WORD AT 'TICNT'

;* SET COUNTER 0 (PRESCALER, 2MHz clock -> 20KHz)
	MVI	A,0x36			;COUNTER 0, LSB+MSB, MODE 3, NOBCD
	OUT	T_CWR
	
;* SOURCE:2MHz,  DEST:20KHz, DIVIDE BY 100 (0x0064)

	MVI	A,0x64			;LSB
	OUT	T_C0
	
	MVI	A,0x00			;MSB
	OUT	T_C0


;* SET COUNTER 1 (TIMER CLOCK, 10Hz)

	MVI	A,0x74			;COUNTER 1, LSB+MSB, MODE 2, NOBCD
	OUT	T_CWR
	
;* SOURCE:20KHz,  DEST:10HZ, DIVIDE BY 2000 (0x07D0)

	MVI	A,0xD0			;LSB
	OUT	T_C1
	
	MVI	A,0x07			;MSB
	OUT	T_C1

;* SET COUNTER 2 (SOUND, SOURCE = 20KHZ)

	MVI	A,0xB6			;COUNTER 2, LSB+MSB, MODE 3, NOBCD
	OUT	T_CWR

	RET

;*********************************************************
;* INTTI0:  INTERRUPT HANDLER FOR TIMER 0. INCREMENTS TICNT
INTTI0:
	PUSH	H
	
	LHLD	TICNT
	INX	H
	SHLD	TICNT
	POP	H
	
	EI
	RET

;*********************************************************
;* IO_DELAY, WAITS ACC * 100MS
IO_DELAY::
	PUSH 	PSW
	PUSH 	H
	PUSH	D

	LHLD	TICNT			;LOAD CURRENT COUNT IN H-L

	MOV	E,A			;COUNT IN D-E
	MVI	D,0
	
	DAD	D			;ADD TO H-L
	
	XCHG				;EXCHANGE D&E, H&L, TARGET NOW IN D-E
	
DLOOP:	LHLD	TICNT			;LOAD CURRENT COUNT IN H-L

	MOV	A,H			;MSB IN A
	XRA	D			;COMPARE WITH MSB OF TARGET
	JNZ	DLOOP			;DIFFERENT -> LOOP
	
	MOV	A,L			;LSB IN A
	XRA	E			;COMPARE WITH LSB OF TARGET
	JNZ	DLOOP			;DIFFERENT -> LOOP	
	
;* WE ARE DONE!
	
	POP	D
	POP	H
	POP 	PSW
	RET

;*********************************************************
;* IO_INITUART:  INITIALIZES UART
IO_INITUART::
	PUSH	PSW
	
	MVI	A,0xA0			;SET DLA MODE
	OUT	U_LCR		
	
	MVI	A,0x0D		;BAUD RATE SETUP
	OUT	U_DLL			;9600 BAUDS (SOURCE 2MHz)
	MVI	A,0x00		
	OUT	U_DLM
	
	MVI	A,0x03			;LCR SETUP
	OUT	U_LCR			;8 DATA, 1 STOP, NO PARITY, DLA_OFF
	
	MVI	A,0x01			;INTERRUPT ENABLE REGISTER
	OUT	U_IER			;ENABLE RECEIVED DATA AVAILABLE INTERRUPT
	
	POP	PSW
	RET

;*********************************************************
;* INTUART:  INTERRUPT HANDLER FOR UART (STUFF A CHAR IN THE KB BUFFER)
INTUART:
	PUSH	PSW
	PUSH	D
	PUSH	H
	
	LHLD	IOKBUFPTR		;LOAD HL WITH WORD AT IOKBUFPTR

	MOV	A,H			;HI PTR IN A
	INR	A			;HI PTR + 1
	ANI	0x0F			;HI PTR MOD 16
	MOV	H,A			;BACK IN H
	
	CMP	L			;COMPARE NEW HI PTR WITH LO PTR	

	JZ	BUFFULL			;IF PTRS ARE EQUAL, BUFFER IS FULL
	
	SHLD	IOKBUFPTR		;PUT BACK UPDATED PTR AT IOKBUFPTR

	DCR	A			;HI PTR -1
	ANI	0x0F			;HI PTR MOD 16
	
	MOV	E,A			;0-H IN D-E (OFFSET TO ADD TO BUF ADDRESS)
	MVI	D,0
		
	LXI	H,IOKBUF		;ADDRESS OF KB BUF IN H-L
	
	DAD	D			;NEW ADDRESS IN H-L

	IN	U_RBR			;GET THE BYTE
	
	MOV	M,A			;NEW CHAR READ -> KB BUFFER
	
	JMP 	IUARTEND
BUFFULL:
	IN	U_RBR			;GET THE BYTE, DO NOTHING WITH IT

IUARTEND:
	POP	H
	POP 	D
	POP	PSW
	EI
	RET

;********************************************************
; IO_GETCHAR:  GETS A CHAR FROM KEYBOARD BUFFER (RETURNED IN ACC - 0 IF EMPTY)
IO_GETCHAR::
	PUSH	B
	PUSH	D
	PUSH	H
	
	LHLD	IOKBUFPTR		;LOAD HL WITH WORD AT IOKBUFPTR

	MOV	A,L			;LO PTR IN A
	
	CMP	H			;COMPARE LO PTR WITH HI PTR
	
	JZ	BUFEMPTY		;IF PTRS ARE EQUAL, BUFFER IS EMPTY

	MOV	C,L			;0-L IN B-C (OFFSET TO ADD TO BUF ADDRESS)
	MVI	B,0

	XCHG				;HL <-> DE
		
	LXI	H,IOKBUF		;ADDRESS OF KB BUF IN H-L
	
	DAD	B			;NEW ADDRESS IN H-L
	
	MOV	B,M			;KB BUFFER -> B
	MOV	A,B			;(TODO: REMOVE)
	OUT	U_THR			;SEND IT BACK (TODO: REMOVE)	

	XCHG				;HL <-> DE

	MOV	A,L

	INR	A			;LO PTR + 1
	ANI	0x0F			;LO PTR MOD 16
	MOV	L,A			;BACK IN LO

	SHLD	IOKBUFPTR		;PUT BACK UPDATED PTR AT IOKBUFPTR
	
	MOV	A,B		
	
	JMP 	IOGETEND
	
BUFEMPTY:
	MVI	A,0			;NOTHING IN BUFFER

IOGETEND:
	POP	H
	POP 	D
	POP	B
	RET

;********************************************************
; IO_PUTC: SENDS A CHAR (FROM ACC) TO THE TERMINAL
IO_PUTC::
	PUSH	PSW
	
1$:	
	IN	U_LSR			;LINE STATUS REGISTER
	ANI	0x20			;CHECK IF UART IS READY
	JZ	1$			;IF NOT, WAIT FOR IT

	POP	PSW			;GET BACK CHAR

	OUT	U_THR	
	
	RET

;*********************************************************
;* KEYBOARD ROUTINES
;*********************************************************
WAITFORCHAR:
1$:
	CALL	IO_GETCHAR	;CHECK TERMINAL
	ORA	A
	JZ	1$
	
;	CALL	FB_PUTC		;SEND BACK
	RET




;*********************************************************
;* IO_INITKBBUF:  INITIALIZES KEYBOARD BUFFER
IO_INITKBBUF::
	LXI	H,0			;HL = 0
	SHLD	IOKBUFPTR		;WORD AT IOKBUFPTR = 0
	RET

; NOTE FREQUENCIES CALCULATED FROM BASE = 2MHz
NOTES: 
	.dw	0xEEE4,0xE17C,0xD4D4,0xC8E2,0xBD9C,0xB2F7,0xA8EC,0x9F71,0x967E,0x8E0C,0x8613,0x7E8C
	.dw	0x7772,0x70BE,0x6A6A,0x6471,0x5ECE,0x597C,0x5476,0x4FB8,0x4B3F,0x4706,0x4309,0x3F46
	.dw	0x3BB9,0x385F,0x3535,0x3238,0x2F67,0x2CBE,0x2A3B,0x27DC,0x259F,0x2383,0x2185,0x1FA3
	.dw	0x1DDD,0x1C2F,0x1A9A,0x191C,0x17B3,0x165F,0x151D,0x13EE,0x12D0,0x11C1,0x10C2,0x0FD2
	.dw	0x0EEE,0x0E18,0x0D4D,0x0C8E,0x0BDA,0x0B2F,0x0A8F,0x09F7,0x0968,0x08E1,0x0861,0x07E9
	.dw	0x0777,0x070C,0x06A7,0x0647,0x05ED,0x0598,0x0547,0x04FC,0x04B4,0x0470,0x0431,0x03F4
	.dw	0x03BC,0x0386,0x0353,0x0324,0x02F6,0x02CC,0x02A4,0x027E,0x025A,0x0238,0x0218,0x01FA


; NOTE FREQUENCIES CALCULATED FROM BASE = 1.8432MHz
;NOTES:	
;	.dw	0xDC29,0xCFCE,0xC424,0xB922,0xAEBE,0xA4EF,0x9BAE,0x92F1,0x8AB1,0x82E9,0x7B90,0x74A0
;	.dw	0x6E15,0x67E7,0x6212,0x5C91,0x575F,0x5278,0x4DD7,0x4978,0x4559,0x4174,0x3DC8,0x3A50
;	.dw	0x370A,0x33FA,0x3109,0x2E49,0x2BB0,0x293C,0x26EB,0x24BC,0x22AC,0x20BA,0x1EE4,0x1D28
;	.dw	0x1B85,0x19FA,0x1885,0x1724,0x15D8,0x149E,0x1376,0x125E,0x1156,0x105D,0x0F72,0x0E94
;	.dw	0x0DC3,0x0CFD,0x0C42,0x0B92,0x0AEC,0x0A4F,0x09BB,0x092F,0x08AB,0x082F,0x07B9,0x074A
;	.dw	0x06E1,0x067E,0x0621,0x05C9,0x0576,0x0527,0x04DD,0x0498,0x0456,0x0417,0x03DC,0x03A5
;	.dw	0x0371,0x033F,0x0311,0x02E5,0x02BB,0x0294,0x026F,0x024C,0x022B,0x020C,0x01EE,0x01D3


;*********************************************************
;* RAM VARIABLES
;*********************************************************

.area	DATA	(REL,CON)

TEMPBYTE:		.ds	1

TICNT:		.ds	2			;TIMER - COUNTER

IOKBUF:		.ds	16			;KEYBOARD BUFFER
IOKBUFPTR:	.ds	2			;KEYBOARD BUFFER - BEGIN/END PTR

