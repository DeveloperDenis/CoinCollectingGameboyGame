;;; Denis Levesque
;;; main.asm - simple Gameboy coin collecting game

VBLANK_FUNCTION EQUS "VBlankFunction"

INCLUDE "../../gameboy_header.inc"

;****************************************************************************************************************************************************
;*	Program Start
;****************************************************************************************************************************************************

	SECTION "Program Start",ROM0[$0150]
Start::

	;; some notes, the stack pointer defaults to $FFFE and the stack grows up
	;; also the stack RAM is from $FFFE to $FF80
	ld	sp, $FFF4 	;the gameboy likes the stack pointer to be here

	;; ldh means "LoaD Hardware register", like the LCD Controller or Status
	;; registers, or the interrupt enable register
	
	;; enable only vblank interrupts
	ld	a, 1 		;vblank interrupt bit = bit 0
	ldh 	[$FF], a	;interrupt enable register is at $FFFF

	;; initialize the display
	; SHOULD WAIT UNTIL V-BLANK BEFORE TURNING OFF SCREEN
wait_vblank::
	ldh	[$41], a
	and	a, %00000010
	jr	nz, wait_vblank

	sub 	a 		;set a to 0
	ldh	[$40], a	;reset LCDC register (turn off lcd)

	ldh	[$42], a	;reset the BG screen scroll to (0,0)
	ldh 	[$43], a

	;; now we need to load some new data to VRAM (instead of the
	;; nintendo logo)
	;; we will load our tiles into the Tile Pattern Table at $8000-$8FFF
	ld	hl, $8000	; the location to write tile data to
	ld	bc, TileData	; the data to write
	ld	e, $30		; the number of bytes we will write
	ld	d, $0
	call	MemCopy

	;; now we load the tile map into vram
	ld	hl, $9800	; location to write tile map to
	ld 	bc, MapData
	ld	de, 32 * 32	; size of the tile map we are writing (max size)
	call	MemCopy

	;; initialize the palettes
	ld	a, %11100100	;the default (i think)

	ldh	[$47], a	; background palette
	ldh	[$48], a	; sprite palette 1
	ldh	[$49], a	; sprite palette 2

	; loading the sprite attribute data to RAM
	ld	bc, SpriteData
	ld	hl, $C000
	ld	d, $0
	ld	e, $8
	call	MemCopy

	; now we are initializing the rest of the unused sprite data
	ld	a, $FF
	ld	d, 38*4
load_sprite_loop::
	ld	a, [bc]
	ldi	[hl], a
	inc	bc
	dec	d
	jr	nz, load_sprite_loop

	; now we want to load our DMA waiting function into HRAM ($FF80)
	ld	bc, DMA_Function
	ld	e, $8		;8 bytes of data
	ld	d, $0
	ld	hl, $FF80
	call	MemCopy

	; initialize the flag that changes player movement
	ld	hl, $D000
	ld	a, $0
	ld	[hl], a

	; initialize the timer
	; we use the timer to randomly position the coin around the screen
	ld	a, $0
	ld	[$FF06], a	; not sure if necessary
	
	ld	a, $1		; you should start the timer (by setting bit 2) after selecting the clock rate of the timer
	ld	[$FF07], a
	ld	a, $5
	ld	[$FF07], a

	; reenable lcd
	ld	a, %11010011		; window display data is at $9C00, background display data is at $9800
	ldh	[$40], a

	;; interrupts can now start happening
	ei

GameLoop::
	; $FF00 is the controller input register
	; bit 4 and 5 control which row of the input matrix we want to read from
	; a value of 0 means we are requesting to read from that location
	ld	a, %00100000
	ldh	[$00], a
	
	; now we read the controller data
	; a value of 0 means the button was pressed
	ldh	a, [$00]	
	ldh	a, [$00]
	ldh	a, [$00] ;how many times should I read from the register before the values stabilize?
	
	; $C000 is the byte for the Y value of the sprite
	; $C001 is the byte for the X value of the sprite
	; bits in $FF00 are as follows: bit 0 = RIGHT, bit 1 = LEFT, bit 2 = UP, bit 3 = DOWN
	ld	hl, $C000
	ld	b, [hl]		; b holds the y value
	inc	hl
	ld	d, [hl]		; d holds the x value
	
	cpl
	or	a
	jr	z, endMovement
	ld	c, a
	
	and	%00001000	;moved down
	jr	z, moveUp
	ld	e, $3		;keep track of where we moved
	inc	b
	inc	b
moveUp::
	ld	a, c
	and	%00000100
	jr	z, moveLeft
	inc	e
	dec	b
	dec	b
moveLeft::
	ld	a, c
	and	%00000010
	jr	z, moveRight
	ld	a, $30		; keep track of where we moved
	or	e
	ld	e, a
	dec	d
	dec	d
moveRight::
	ld	a, c
	and	%00000001
	jr	z, endMovement
	ld	a, e
	add	%00010000
	ld	e, a
	inc	d
	inc	d
endMovement::
	; did we move diagonally?
	ld	a, e
	and	%00100000
	ld	c, a
	ld	a, e
	and	%00000010
	or	c
	xor	%00100010		;bottom left
	jr	nz, secondCheck
	
	ld	a, [$D000]
	or	a
	cpl
	ld	[$D000], a
	jr	nz, .altBranch
	dec	b
	jr	updateXY
.altBranch
	inc	d
	jr	updateXY
secondCheck::
	ld	a, e
	and	%00100000
	ld	c, a
	ld	a, e
	and	%00000001
	or	c
	xor	%00100001		; top left
	jr	nz, thirdCheck
	
	ld	a, [$D000]
	or	a
	cpl
	ld	[$D000], a
	jr	nz, .altBranch
	inc	d
	jr	updateXY
.altBranch
	inc	b
	jr	updateXY
thirdCheck::
	ld	a, e
	and	%00010000
	ld	c, a
	ld	a, e
	and	%00000010
	or	c
	xor	%00010010		;bottom right
	jr	nz, fourthCheck

	ld	a, [$D000]
	or	a
	cpl
	ld	[$D000], a
	jr	nz, .altBranch
	dec	b
	jr	updateXY
.altBranch
	dec	d
	jr	updateXY
fourthCheck::
	ld	a, e
	xor	%00010001		; top right
	jr	nz, updateXY
	
	ld	a, [$D000]
	or	a
	cpl
	ld	[$D000], a
	jr	nz, .altBranch
	inc	b
	jr	updateXY
.altBranch
	dec	d
updateXY::
	; finally we update the sprite values in memory
	ld	[hl], d
	dec	hl
	ld	[hl], b
	
	; collision detection
	ld	e, $0
	ld	a, [$C000] ; Y pos of player
	inc	a	; slightly decrease hitbox of player
	ld	b, a
	ld	a, [$C004] ; Y pos of coin
	ld	c, a

	; check if the player is within the y bounds of the coin
	cp	b
	jr	nc, vertCollision
	add	a, $6	; not 8 because of the hitbox decrease
	cp	b
	jr	c, horzCollision
	ld	e, $1
	jr	horzCollision
vertCollision::
	ld	a, b
	add	$8
	cp	c
	jr	c, horzCollision
	ld	e, $1
horzCollision::
	ld	a, [$C001] ; X pos of player
	add	$2	; we decrease the hitbox of the player a bit to be more realistic given his shape
	ld	b, a
	ld	a, [$C005] ; X pos of coin
	ld	c, a

	; check if the player is within the x bounds of the coin
	cp	b
	jr	c, .collisionCheck2
	ld	a, b
	add	$4	; again decreasing the hitbox of the player
	cp	c
	jr	c, collisionUpdate
	ld	a, e
	or	$2
	ld	e, a
	jr	collisionUpdate
.collisionCheck2
	add	$8
	cp	b
	jr	c, collisionUpdate
	ld	a, e
	or	$2
	ld	e, a
collisionUpdate::
	; if register e bits 0 and 1 are set, then the player is within the bounding box of the coin
	ld	a, e
	xor	%00000011
	jr	nz, noCollision
	
	; calculate the next random number
	ld	a, [$FF05]
	and	%01111111
	add	$15
	ld	[$C004], a
	
	ld	a, [$FF04]
	and	%01111111
	add	$10
	ld	[$C005], a
noCollision::
	
	ld	e, $0
	halt
	jp	GameLoop

; before runing MemCopy:
; HL should hold the location to write to
; BC should hold the location to write from
; DE should hold the number of bytes to write
MemCopy:
	push	af
	
.copyLoop
	ld		a, [bc]
	ldi		[hl], a
	inc		bc

	dec		de
	
	ld		a, e
	or		a
	jp		nz, .copyLoop
	ld		a, d
	or		a
	jp		nz, .copyLoop

	pop		af
	ret

VBlankFunction::
	di		; disable interrupts (don't think this is necessary?)
	push	af	; we push the flag register so that the interrupted code will still
			; execute as expected, and we use A so we should push that too

	ld	a, $C0
	call	$FF80	; perform the DMA transfer of sprite data

	pop	af
	ei	; enable interrupts
	reti

DMA_Function::
DB	$E0, $46, $3E, $28
DB	$3D, $20, $FD, $C9

SpriteData::
DB	$40, $40, $01, $00	; player sprite
DB	$64, $50, $02, $00	; coin sprite

TileData::
DB	$20, $00, $02, $00, $80, $00, $08, $00
DB	$00, $00, $00, $00, $21, $00, $00, $00
DB 	$00, $3C, $3C, $42, $3C, $66, $3C, $42
DB 	$00, $3C, $00, $3C, $00, $3C, $00, $3C
DB 	$3C, $00, $60, $1E, $5A, $26, $5A, $2E
DB	$5A, $2E, $5A, $2E, $06, $7E, $3C, $3C

MapData::
; 32 x 32 tiles
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DB	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
