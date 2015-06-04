; ECAD by Timur "XProger" Gagiev
; xproger@list.ru
; tips: 1 tab = 10 spaces

; defines
USE_GAMMA_CORRECTION = 1
;USE_LAYER_OPACITY = 1
USE_DEBUG = 1
MODE_BENCHMARK = 1
WINDOWS = 1
include 'win32a.inc'
;include 'macros.inc'

if defined WINDOWS				; Windows
	if defined USE_DEBUG
		format PE CONSOLE 4.0
	else
		format PE GUI 4.0
	end if
	entry START

	section '.' import data readable writeable executable
		library kernel32,'KERNEL32.DLL', user32,'USER32.DLL', gdi32,'GDI32.DLL',msvcrt,'msvcrt.dll'
		if defined USE_DEBUG
			import msvcrt, printf, 'printf'
		end if
		include 'api\kernel32.inc'
		include 'api\user32.inc'
		include 'api\gdi32.inc'
else					; KolibriOS
	format binary as "kex"
	use32
	org	0
	db	'MENUET01'
	dd	1, START, I_END, IM_END+2048, IM_END+2048, 0, 0

	struct FILE_TIME
		sec	db ?
		min	db ?
		hour	db ?
		res	db ?
	ends

	struct FILE_DATE
		day	db ?
		month	db ?
		year	dw ?
	ends

	struct FILE_REQ
		arg1	dd ?
		arg2	dd ?
		arg3	dd ?
		arg4	dd ?
		arg5	dd ?
		arg6	db ?
		arg7	dd ?
	ends

	struct FILE_INFO
		attr	dd ?
		ntype	db ?
		res1	db ?
		res2	db ?
		res3	db ?
		ctime	FILE_TIME
		cdate	FILE_DATE
		tread	FILE_TIME
		dread	FILE_DATE
		twrite	FILE_TIME
		dwrite	FILE_DATE
		filesize	dd ?
		filename	db ?
	ends

	struct BLIT_INFO
		dstx	dd ?
		dsty	dd ?
		dstw	dd ?
		dsth	dd ?
		srcx	dd ?
		srcy	dd ?
		srcw	dd ?
		srch	dd ?
		bitmap	dd ?
		stride	dd ?
	ends
end if

struct	VEC2
	x	dd ?
	y	dd ?
ends

struct	VEC4
	x	dd ?
	y	dd ?
	z	dd ?
	w	dd ?
ends

struct	BOARD_TRACK
	pos1	VEC2
	pos2	VEC2
	w	dd ?
	flags	dd ?
	sexp	dd ?
	pexp	dd ?
ends

struct	BOARD_PAD
	pos	VEC2
	size	VEC2
	hole	VEC2
	sexp	dd ?
	pexp	dd ?
	flags	dd ?
	res1	dd ?
	res2	dd ?
	res3	dd ?
ends

struct	BOARD_LAYER_INFO
	index	dd ?
	color	dd ?
	tCount	dd ?
	pCount	dd ?
ends

struct	BOARD_LAYER
	info	BOARD_LAYER_INFO
	tracks	dd ?
	pads	dd ?
ends

struct	VIEW
	trans	VEC4
	scale	VEC4
ends

struct	BOARD
	view	VIEW
	count	dd ?
	layers	dd ?
ends

struct	CANVAS
	width	dd ?	; width (aligned on 4)
	height	dd ?	; height
	size	dd ?	; width * height * 4
	bytes	dd ?	; memory (aligned on 16 bytes) udata + offset 0-15
ends

struct	MOUSE
	state	dd ?
	pos	VEC2
	last	VEC2
	origin	VEC2
ends

; SSE global variable aliases
xcam_min		equ xmm4
xcam_max		equ xmm5
xcam_trans	equ xmm6
xcam_scale	equ xmm7

; mouse states
MOUSE_STATE_NONE	equ 0
MOUSE_STATE_MOVE	equ 1
MOUSE_STATE_ZOOM	equ 2

; color constants
COLOR_BACKGROUND	equ 0x00000000
COLOR_SMT_HOLE	equ 0x00009190
COLOR_THT_HOLE	equ 0x00816200

; pad flags
PAD_FLAG_THT	equ 1 shl 15

; menu commands
MC_FILE_NEW		equ 00
MC_FILE_OPEN		equ 01
MC_FILE_SAVE		equ 02
MC_FILE_SAVE_AS		equ 03
MC_FILE_EXIT		equ 04

MC_EDIT_UNDO		equ 05
MC_EDIT_REDO		equ 06
MC_EDIT_CUT		equ 07
MC_EDIT_COPY		equ 08
MC_EDIT_PASTE		equ 09
MC_EDIT_DELETE		equ 10
MC_EDIT_SELECT_ALL		equ 11

MC_VIEW_FLIP		equ 12

MC_TOOLS_TRACK		equ 13
MC_TOOLS_PAD		equ 14
MC_TOOLS_REGION		equ 15
MC_TOOLS_COMPONENT		equ 16

MC_TOOLS_MEASURE_LINEAR	equ 17
MC_TOOLS_MEASURE_ANGULAR	equ 18

ACCEL_COUNT		equ 19

; ==== System =================================================================
; align allocated memory
; in:	eax = memory ptr (size + 32)
; out:	eax = aligned memory address
System.malign:
	mov	ecx, eax
	add	ecx, 15
	and	ecx, not 15
	mov	[ecx], eax
	mov	eax, ecx
	add	eax, 16
	ret

; allocate 16-byte aligned memory block
; in:	ecx = size
; out:	eax = memory ptr
System.malloc:
	push	ecx
	add	ecx, 32
	if defined WINDOWS
		push	esi
		push	edi
		push	ebx
		push	edx
		invoke	HeapAlloc,[sys_heap],0,ecx
		pop	edx
		pop	ebx
		pop	edi
		pop	esi
	else
		mcall	68, 12, ecx
	end if
	call	System.malign
	pop	ecx
	ret

; reallocate memory block
; in:	eax = memory ptr
;	ecx = new size
; out:	eax = memory ptr
System.realloc:
	add	ecx, 32
	sub	eax, 16
	if defined WINDOWS
		invoke	HeapReAlloc,[sys_heap],0,[eax],ecx
	else
		mov	edx, [eax]
		mcall	68, 20, ecx, edx
	end if
	call	System.malign
	ret

; free memory block
; in:	eax = memory ptr
System.free:
	sub	eax, 16
	if defined WINDOWS
		invoke	HeapFree,[sys_heap],0,[eax]
	else
		mov	ecx, [eax]
		mcall	68, 13, ecx
	end if
	ret

if defined USE_GAMMA_CORRECTION
	System.initGammaLUT:
		mov	ecx, 255
		;movss	xmm1, [SSE_1f]
		;movss	xmm2, [SSE_255f]
		movss	xmm1, [SSE_MATH + 4]
		movss	xmm2, [SSE_MATH + 12]
		divss	xmm1, xmm2
	@@:	cvtsi2ss	xmm0, ecx
		mulss	xmm0, xmm1		; /= 255.0f

		movss	xmm3, xmm0
		movss	xmm4, xmm0

		mulss	xmm3, xmm3		; sqr
		sqrtss	xmm4, xmm4		; sqrt

		mulss	xmm3, xmm2		; *= 255.0f
		mulss	xmm4, xmm2

		cvttss2si	eax, xmm3			; convert to int
		cvttss2si	ebx, xmm4

		mov	[LUT_gamma2color + ecx], al
		mov	[LUT_color2gamma + ecx], bl

		dec	ecx
		jnl	@b

		ret
end if

System.memcpy_SSE:
	; TODO: System.memcpy ebx -> edi, sizeof.BOARD_LAYER_INFO
	push	eax
	push	ecx
	push	edi
	push	esi

if 1 = 0
	shr	ecx, 4	; count /= 16
@@:	movaps	xmm0, [esi]
	movaps	[edi], xmm0
	add	esi, 16
	add	edi, 16
else
	shr	ecx, 2	; count /= 16
@@:	mov	eax, [esi]
	mov	[edi], eax
	add	esi, 4
	add	edi, 4
end if
	dec	ecx
	jnz	@b

	pop	esi
	pop	edi
	pop	ecx
	pop	eax
	ret

; fill memory by 32-bit value
; in:	eax - value
;	ebx - data pointer
;	ecx - data size
System.memset32_sse:
	shr	ecx, 6	; div data size by 16 bytes
	movd	xmm0, eax
	shufps	xmm0, xmm0, 0
@@:	movaps	[ebx + 00h], xmm0
	movaps	[ebx + 10h], xmm0
	movaps	[ebx + 20h], xmm0
	movaps	[ebx + 30h], xmm0
	add	ebx, 40h
	dec	ecx
	jnz	@b
	ret

System.time:
	if defined WINDOWS
		invoke	GetTickCount
	else
		mcall	26, 9
		imul	eax, 10
	end if
	ret

; ==== Window =================================================================
START:
	call	Window.Init
	mov	eax, filename
	call	Board.Load

@@:	if defined WINDOWS
		if defined MODE_BENCHMARK
			invoke	PeekMessage,msg,0,0,0,PM_REMOVE
			test	eax, eax
			jnz	.event
			call	Window.Repaint
			jmp	@b
		else
			invoke	GetMessage,msg,0,0,0
			test	eax, eax
			jz	.exit
			jmp	.event
			jmp	@b
		end if

		.event:	invoke	TranslateAccelerator,[hwnd],[haccel],msg
			test	eax, eax
			jnz	@b
			invoke	TranslateMessage,msg
			invoke	DispatchMessage,msg
			mov	eax, [msg.message]
			cmp	eax, WM_QUIT
			je	.exit
			jmp	@b
	else
		.redraw:	call	Window.Repaint
		.loop:	if defined MODE_BENCHMARK
				mcall	11		; check for event
				test	eax, eax
				jz	.redraw
			else
				mcall	10
			end if
			dec	eax
			jz	.redraw
			dec	eax
			jz	.key
			dec	eax
			jz	.button
			cmp	eax, 3
			je	.mouse
			jmp	.loop
		.key:	mcall	2
			jmp	.loop
		.button:	mcall	17
			cmp	ah, 1
			jne	.loop
			jmp	.exit
		.mouse:	call	Window.Mouse.Update
			;mcall	63, 1, 49
		.vzoom:	mcall	37, 7	; wheel-delta
			movsx	eax, ax
			test	eax, eax
			jz	.vmove
			movq	mm0, [mouse.pos]
			movq	[mouse.origin], mm0
			sal	eax, 4
			call	Board.View.Zoom	; zoom
		.vmove:	mcall	37, 2	; check buttons
			cmp	eax, 1
			jne	.loop
			call	Board.View.Move
			jmp	.loop
	end if

.exit:	mov	eax, [canvas.bytes]
	call	System.free
	if defined WINDOWS
		invoke	ExitProcess,0
	else
		mcall	-1
	end if


if defined WINDOWS
proc WndProc hwnd,wmsg,wparam,lparam
	mov	ecx, [wmsg]
	cmp	ecx, WM_PAINT
	je	.paint
	cmp	ecx, WM_MOUSEMOVE
	je	.mouse.move
	cmp	ecx, WM_LBUTTONDOWN
	je	.mouse.button.down.L
	cmp	ecx, WM_RBUTTONDOWN
	je	.mouse.button.down.R
	cmp	ecx, WM_LBUTTONUP
	je	.mouse.button.up
	cmp	ecx, WM_RBUTTONUP
	je	.mouse.button.up
	cmp	ecx, WM_MOUSEWHEEL
	je	.mouse.wheel
	cmp	ecx, WM_SIZE
	je	.size
	cmp	ecx, WM_GETMINMAXINFO
	je	.minmax
	cmp	ecx, WM_COMMAND
	je	.command
	cmp	ecx, WM_DESTROY
	je	.destroy
	invoke	DefWindowProc,[hwnd],[wmsg],[wparam],[lparam]
	ret
.paint:
	if 1 = 0
		movaps	xmm0, [board.view.scale]
		rcpps	xmm0, xmm0
		cvttps2pi	mm0, xmm0
		movq	[v0], mm0
		mov	eax, [v0.x]
		cvttps2pi	mm0, [board.view.trans]
		movq	[v0], mm0
		if defined USE_DEBUG
			cinvoke	printf,d_view,[v0.x],[v0.y],eax
		end if
	end if

	locals
		ps	PAINTSTRUCT
	endl

	
	call	Window.Render	
	
	lea	esi, [ps]
	invoke	BeginPaint,[hwnd],esi
	invoke	SetDIBitsToDevice,[ps.hdc],0,0,[canvas.width],[canvas.height],0,0,0,[canvas.height],[canvas.bytes],bmi,0
	invoke	EndPaint,[hwnd],esi

	if defined USE_DEBUG
		inc	[frame]
		call	System.time
		cmp	eax, [frame_time]
		jl	.return0
		add	eax, 1000
		mov	[frame_time], eax
		cinvoke	printf,d_fps,[frame]
		mov	[frame], 0
	end if
	jmp	.return0

.mouse.move:
	call	Window.Mouse.Update
	mov	ecx, [mouse.state]
	test	ecx, ecx	; MOUSE_STATE_NONE
	jz	.return0
	cmp	ecx, MOUSE_STATE_ZOOM
	je	@f
	; move
	call	Board.View.Move
	jmp	.return0
	; zoom
	; xmm0 = delta = pos - last
@@:	mov	eax, [mouse.pos.y]
	sub	eax, [mouse.last.y]
	call	Board.View.Zoom
	jmp	.return0

.mouse.button.down.R:
	call	Window.Mouse.Update
	mov	[mouse.state], MOUSE_STATE_ZOOM
	movq	mm0, [mouse.pos]
	movq	[mouse.origin], mm0		; mouse origin (for zoom) = mouse pos
	jmp	.mouse.button.down
.mouse.button.down.L:
	call	Window.Mouse.Update
	mov	[mouse.state], MOUSE_STATE_MOVE
.mouse.button.down:
	invoke	SetCapture,[hwnd]
	jmp	.return0

.mouse.button.up:
; TODO: check button ----------------------------------------------------
	mov	[mouse.state], MOUSE_STATE_NONE
	invoke	ReleaseCapture
	jmp	.return0

.mouse.wheel:
	mov	ecx, [mouse.state]
	test	ecx, ecx
	jnz	.return0	; not MOUSE_STATE_NONE
	call	Window.Mouse.Update
	movq	mm0, [mouse.pos]
	movq	[mouse.origin], mm0	; mouse origin (for zoom) = mouse pos
	movsx	eax, word [wparam + 2]
	cdq
	mov	ecx, 120
	idiv	ecx
	sal	eax, 4		; 1 wheel step = 16 zoom value
	neg	eax
	call	Board.View.Zoom
	jmp	.return0

.size:
	; get width & height of client area
	movzx	eax, word [lparam]
	movzx	ebx, word [lparam + 2]
	test	ebx, ebx
	jz	.return0
	add	eax, 3		; align width by 4 canvas.bytes (16 bytes for SSE)
	and	eax, not 3
	call	Window.Resize
	invoke	DrawMenuBar,[hwnd]
	jmp	.return0
.minmax:
	virtual at eax
		.mm MINMAXINFO
	end virtual

	mov	eax, [lparam]
	mov	[.mm.ptMinTrackSize.x], 320
	mov	[.mm.ptMinTrackSize.y], 240
	jmp	.return0
.command:
	movzx	ecx, word [wparam]
	if defined USE_DEBUG
		pushad
		cinvoke	printf,d_count,ecx
		popad
	end if
	cmp	ecx, MC_FILE_EXIT
	jne	@f
	jmp	.destroy

@@:	
	jmp	.return0
.destroy:
	invoke	PostQuitMessage,0
.return0:
	xor	eax, eax
	ret
endp
end if

Window.Init:
	; init memory heap
	if defined WINDOWS
		invoke	GetProcessHeap
		mov	[sys_heap], eax
	else
		mcall	68, 11
	end if

	mov	ecx, 16
	call	System.malloc
	mov	[canvas.bytes], eax
	if defined USE_GAMMA_CORRECTION
		call	System.initGammaLUT
	end if

	mov	[board.count], 0

	if defined WINDOWS
		; create window
		call	Window.InitMenu		
		invoke	CreateWindowEx,0,WND_CLASS,WND_TITLE,WS_OVERLAPPEDWINDOW,0,0,1024,600,0,[hmenu],0,0
		mov	[hwnd], eax
		invoke	SetWindowLong,[hwnd],GWL_WNDPROC,WndProc
	else
		mcall	40, EVM_REDRAW + EVM_KEY + EVM_BUTTON + EVM_MOUSE	; events filter
		mcall	12, 1
		mcall	0, <0,1024>, <0,600>, 0x73000000, , WND_TITLE
		mcall	12, 2
	end if

	mov	[mouse.state], MOUSE_STATE_NONE

	movaps	xcam_trans, dqword [cam_trans]
	movlhps	xcam_trans, xcam_trans

	movss	xcam_scale, [cam_scale]
	rcpss	xcam_scale, xcam_scale
	shufps	xcam_scale, xcam_scale, 0
	xorps	xcam_scale, dqword [SSE_SIGN_MASK]

	movaps	dqword [board.view.trans], xcam_trans
	movaps	dqword [board.view.scale], xcam_scale

	if defined USE_DEBUG
		call	System.time
		mov	[frame_time], eax
		mov	[frame], 0
	end if
	if defined WINDOWS
		invoke	ShowWindow,[hwnd],SW_SHOWDEFAULT
	end if
	ret

Window.InitMenu:
	invoke	CreateMenu
	mov	[hmenu], eax
	; File
	invoke	CreatePopupMenu
	mov	[v0], eax
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_FILE_NEW,m_file_new
	invoke	AppendMenu,[v0],MF_STRING,MC_FILE_OPEN,m_file_open
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_FILE_SAVE,m_file_save
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_FILE_SAVE_AS,m_file_save_as
	invoke	AppendMenu,[v0],MF_SEPARATOR,0,0
	invoke	AppendMenu,[v0],MF_STRING,MC_FILE_EXIT,m_file_exit
	invoke	AppendMenu,[hmenu],MF_POPUP,[v0],m_file
	; Edit
	invoke	CreatePopupMenu
	mov	[v0], eax
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_UNDO,m_edit_undo
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_REDO,m_edit_redo
	invoke	AppendMenu,[v0],MF_SEPARATOR,0,0	
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_CUT,m_edit_cut
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_COPY,m_edit_copy
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_PASTE,m_edit_paste
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_DELETE,m_edit_delete
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_EDIT_SELECT_ALL,m_edit_select_all
	invoke	AppendMenu,[hmenu],MF_POPUP,[v0],m_edit
	; View
	invoke	CreatePopupMenu
	mov	[v0], eax
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_VIEW_FLIP,m_view_flip
	invoke	AppendMenu,[hmenu],MF_POPUP,[v0],m_view
	; Place
	invoke	CreatePopupMenu
	mov	[v0], eax
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_TOOLS_TRACK,m_tools_track
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_TOOLS_PAD,m_tools_pad
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_TOOLS_REGION,m_tools_region
	invoke	AppendMenu,[v0],MF_STRING+MF_GRAYED,MC_TOOLS_COMPONENT,m_tools_component
	
	invoke	AppendMenu,[v0],MF_SEPARATOR,0,0
	
	invoke	CreatePopupMenu
	mov	[v0.y], eax
	invoke	AppendMenu,[v0.y],MF_STRING+MF_GRAYED,MC_TOOLS_MEASURE_LINEAR,m_tools_measure_linear
	invoke	AppendMenu,[v0.y],MF_STRING+MF_GRAYED,MC_TOOLS_MEASURE_ANGULAR,m_tools_measure_angular
	invoke	AppendMenu,[v0],MF_POPUP,[v0.y],m_tools_measure	
	invoke	AppendMenu,[hmenu],MF_POPUP,[v0],m_tools

	xor	ecx, ecx
	mov	esi, HOTKEYS
	
	mov	edi, esp
	
@@:	movzx	ax, byte [esi + ecx*2 + 0]	; modifiers
	movzx	dx, byte [esi + ecx*2 + 1]	; key
	or	ax, FVIRTKEY
		
	push	cx	; MC_* menu command id
	push	dx	; key
	push	ax	; modifier
	
	inc	ecx
	cmp	ecx, ACCEL_COUNT
	jne	@b

.done:	mov	[v0.x], esp
	invoke	CreateAcceleratorTable,[v0],ACCEL_COUNT
	mov	[haccel], eax
	mov	esp, edi
	
	ret

Window.Resize:
	mov	[canvas.width], eax
	mov	[canvas.height], ebx
	
	if defined WINDOWS
		; fill bmi (for SetDIBitsToDevice)
		mov	[bmi.biSize], sizeof.BITMAPINFOHEADER
		mov	[bmi.biWidth], eax
		neg	ebx
		mov	[bmi.biHeight], ebx
		neg	ebx
		mov	[bmi.biPlanes], 1
		mov	[bmi.biBitCount], 32
		mov	[bmi.biCompression], BI_RGB
	else
		mov	ecx, [proc_info.client_box.left]
		mov	edx, [proc_info.client_box.top]
		mov	[blit_info.dstx], ecx
		mov	[blit_info.dsty], edx
		mov	ecx, [proc_info.client_box.width]
		mov	[blit_info.dstw], ecx
		mov	[blit_info.dsth], ebx
		mov	[blit_info.srcx], 0
		mov	[blit_info.srcy], 0
		mov	[blit_info.srcw], ecx
		mov	[blit_info.srch], ebx
		mov	ecx, [canvas.bytes]
		mov	[blit_info.bitmap], ecx
		mov	ecx, eax
		shl	ecx, 2
		mov	[blit_info.stride], ecx
	end if
	; get unaligned memory size for canvas.bytes
	mul	ebx
	shl	eax, 2		; *4 (32bpp)
	mov	[canvas.size], eax
	; reallocate memory for canvas.bytes buffer
	mov	ecx, eax
	mov	eax, [canvas.bytes]
	call	System.realloc
	mov	[canvas.bytes], eax

	call	Window.Repaint
	ret

Window.Repaint:
	if defined WINDOWS
		invoke	InvalidateRect,[hwnd],0,0
	else
		mcall	9, proc_info, -1	; get application state
		mov	eax, [proc_info.client_box.width]
		mov	ebx, [proc_info.client_box.height]
		test	ebx, ebx	; height = 0
		jz	.done
		add	eax, 3		; align width by 4 canvas.bytes (16 bytes for SSE)
		and	eax, not 3
		cmp	eax, [canvas.width]
		jne	.resize
		cmp	ebx, [canvas.height]
		jne	.resize
		jmp	.render
	.resize:	call	Window.Resize	; TODO: don't call after moving
	.render:	call	Window.Render
		mcall	12, 1
		mcall	0,,, 0x73000000
		mcall	73, 0, blit_info

		if defined USE_DEBUG
			; update fps info
			mcall	47, (6 shl 16), [fps], <4, 4>, 0xffff00
			inc	[frame]
			call	System.time
			cmp	eax, [frame_time]
			jl	.present
			add	eax, 1000
			mov	[frame_time], eax
			mov	eax, [frame]
			mov	[fps], eax
			mov	[frame], 0
		end if
	.present:	mcall	12, 2
	end if
.done:	ret

Window.Render:
	; setup view to SSE registers
	movaps	xcam_trans, dqword [board.view.trans]
	movaps	xcam_scale, dqword [board.view.scale]

	; setup min/max registers
	xorps	xcam_min, xcam_min			; xcam_min = [0, 0, 0, 0]
	movq	xcam_max, qword [canvas.width]	; xcam_max = [width, height, width, height]
	movlhps	xcam_max, xcam_max
	cvtdq2ps	xcam_max, xcam_max

	movss	xmm0, [SSE_MATH]
	shufps	xmm0, xmm0, 0
	subps	xcam_max, xmm0
	;subps	xcam_max, dqword [SSE_005f]		; xcam_max -= 1.0f

	; prepare for alpha blending
	pxor	mm6, mm6			; zero mm5
	mov	eax, 256
	movd	mm7, eax
	pshufw	mm7, mm7, 0		; mm4 = [256, 256, 256, 256]
	; clear background
	mov	eax, COLOR_BACKGROUND
	mov	ebx, [canvas.bytes]
	mov	ecx, [canvas.size]
	call	System.memset32_sse
	; render board
	call	Board.Render.Layers
	if defined USE_GAMMA_CORRECTION
		call	Window.ApplyGamma
	end if
	emms
	ret

if defined USE_GAMMA_CORRECTION
	Window.ApplyGamma:
		mov	esi, [canvas.bytes]
		mov	ecx, [canvas.size]
		mov	edi, LUT_color2gamma
	@@:   	movzx	eax, byte [esi+0]
		movzx	ebx, byte [esi+1]
		movzx	edx, byte [esi+2]
		mov	al, [edi+eax]
		mov	bl, [edi+ebx]
		mov	dl, [edi+edx]
		mov	[esi+0], al
		mov	[esi+1], bl
		mov	[esi+2], dl
		add	esi, 4
		sub	ecx, 4
		jnz	@b
		ret
end if

Window.Mouse.Update:
	movq	mm0, [mouse.pos]
	movq	[mouse.last], mm0
	lea	esi, [mouse.pos]
	if defined WINDOWS
		invoke	GetCursorPos,esi
		invoke	ScreenToClient,[hwnd],esi
		; invert y
		;mov	eax, [canvas.height]
		;dec	eax
		;sub	eax, [esi + 4]
		;mov	[esi + 4], eax
	else
		mcall	37, 1	; relative mouse pos
		movsx	ebx, ax
		shr	eax, 16
		movsx	ecx, ax
		mov	[esi + 0], ecx	; mouse.pos.x
		mov	[esi + 4], ebx	; mouse.pos.y
	end if
	ret

; ==== Canvas =================================================================
; mca = color * alpha
; mia = 256 - alpha
macro CANVAS_SET_ALPHA col, mca, mia {
	movd	mca, col		; mca = [0, ARGB2]
	movq	mm0, mca		; mm0 = mca
	punpcklbw	mca, mm6		; mca = [0, R2, G2, B2]
	movq	mia, mm7		; mia = [256, 256, 256, 256]
	psrld	mm0, 24		; mm0 = [0,  0,  0, A2]
	pshufw	mm0, mm0, 0	; mm0 = [A2, A2, A2, A2]
	pmullw	mca, mm0		; mca = [0, R2*A2, G2*A2, B2*A2]
	psubw	mia, mm0		; mia = [256 - A2, ...]
}

macro CANVAS_SET_PIXEL dst_ptr, color {
	mov	[dst_ptr], color
}

; Result := (A*alpha + B*(256-alpha))/256
macro CANVAS_SET_PIXELA dst_ptr, mca, mia {
	movd	mm0, [dst_ptr]	; mm0 = [0, ARGB1]
	punpcklbw	mm0, mm6		; mm0 = [0, R1, G1, B1]
	pmullw	mm0, mia		; mm0 = [0, R1, G1, B1] * (256 - A2)
	paddusw	mm0, mca		; mm0 = 0 R1*X+Rb*Y | Ga*X+Gb*y Ba*X+Bb*Y
	psrlw	mm0, 8		; mm0 = 0 0 0 Rc | 0 Gc 0 Bc
	packuswb	mm0, mm0		; mm0 = 0 0 0 0 | 0 Rc Gc Bc
	movd	[dst_ptr], mm0
}

macro PUT_ALPHA_PIXEL color {
	CANVAS_SET_ALPHA color,mm1,mm2
	CANVAS_SET_PIXELA edi,mm1,mm2
}

macro CANVAS_GAMMA_TO_COLOR color {
	if defined USE_GAMMA_CORRECTION
		mov	ebx, LUT_gamma2color
		mov	eax, color
		xlatb
		ror	eax, 8
		xlatb
		ror	eax, 8
		xlatb
		ror	eax, 16
		mov	color, eax
	end if
	and	color, 0x00ffffff
}

macro CANVAS_TRANSFORM xreg {
	; transform by camera
	addps	xreg, xcam_trans	; translate
	mulps	xreg, xcam_scale	; scale
}

macro CANVAS_CLAMP xreg {
	; clamp coords by viewport
	maxps	xreg, xcam_min
	minps	xreg, xcam_max
}

; in:	xmm0 - position
Canvas.Dot:
	movaps	xmm1, xmm0
	CANVAS_TRANSFORM xmm1
	CANVAS_CLAMP xmm1

	cvttps2dq	xmm1, xmm1
	movaps	[v0], xmm1
	; edi = data pointer
	mov	edi, [v0.y]	; y
	imul	edi, [canvas.width]	; *= canvas.width
	add	edi, [v0.x]	; += x
	shl	edi, 2		; *= 4
	add	edi, [canvas.bytes]	; += data ptr
	mov	[edi], esi
	ret

; draw 1px horizontal line with alpha blending
; in:	esi = color
;	edi = dest ptr
;	ecx = width
Canvas.HLineAlpha:
	CANVAS_SET_ALPHA esi,mm1,mm2
	test	ecx, ecx
	js	.done
@@:	CANVAS_SET_PIXELA edi,mm1,mm2
	add	edi, 4		; add offset to next pixel
	dec	ecx
	jns	@b
.done:	ret

Canvas.VLineAlpha:
	CANVAS_SET_ALPHA esi,mm1,mm2
	test	ecx, ecx
	js	.done
@@:	CANVAS_SET_PIXELA edi,mm1,mm2
	add	edi, edx		; add offset to next pixel
	dec	ecx
	jns	@b
.done:	ret

; in:	xmm0 = min.xy, max.xy
;	esi = color
Canvas.Fill:
	CANVAS_GAMMA_TO_COLOR esi
	CANVAS_TRANSFORM xmm0

	movss	xmm2, xcam_scale
	shufps	xmm2, xmm2, 0
	mulps	xmm1, xmm2
	addps	xmm0, xmm1

	CANVAS_CLAMP xmm0

	cvttps2dq	xmm2, xmm0		; xmm2 = (int)xmm0
	movaps	[v0], xmm2

	; culling
	cmp	[v0.z], 0			; if imax.x < 0
	jl	.done
	cmp	[v0.w], 0			; if imax.y < 0
	jl	.done
	mov	eax, [canvas.width]
	mov	ebx, [canvas.height]
	cmp	[v0.x], eax		; if imin.x >= canvas.width
	jge	.done
	cmp	[v0.y], ebx		; if imin.y >= canvas.height
	jge	.done

	; edi = data pointer
	mov	edi, [v0.y]	; y
	imul	edi, eax		; *= canvas.width
	add	edi, [v0.x]	; += x
	shl	edi, 2		; *= 4
	add	edi, [canvas.bytes]	; += data ptr

	; ebx = width
	; eax = height
	; edx = canvas.width
	mov	edx, eax
	mov	ebx, [v0.z]
	mov	eax, [v0.w]
	sub	ebx, [v0.x]
	sub	eax, [v0.y]
	; edx = canvas.width - width (lines stride)
	sub	edx, ebx
	shl	edx, 2			; mul by 4

	; TODO: or eax, ebx ?
	test	eax, eax			; if 1px
	jnz	.rect
	test	ebx, ebx
	jnz	.rect
	; alpha = (max.x - min.x) * (max.y - min.y)
.point:	xorps	xmm1, xmm1
	movhlps	xmm1, xmm0
	subps	xmm1, xmm0	; xmm1 = max - min
	movaps	xmm0, xmm1	; xmm0 = xmm1

	shufps	xmm1, xmm1, 01b	; xmm1 = yx--
	mulss	xmm1, xmm0	; alpha = y * x
	if defined USE_LAYER_OPACITY
		mulss	xmm1, [SSE_MATH + 8]	; alpha *= 128
	else
		mulss	xmm1, [SSE_MATH + 12]	; alpha *= 255
	end if
	cvttss2si	eax, xmm1
	shl	eax, 24
	or	esi, eax
	PUT_ALPHA_PIXEL eax
	ret
; NxN px rect
.rect:	cvtdq2ps	xmm2, xmm2		; xmm2 = trunc(xmm0) (float)
	; get size delta (i.e. alpha for 1px)
	movaps	xmm1, xmm0		; xmm1 = [min, max]
	movhlps	xmm1, xmm0		; xmm1 = [max, max]
	subps	xmm1, xmm0		; xmm1 = [max - min, max - max]
	movlhps	xmm1, xmm1		; xmm1 = [max - min, max - min]
	; get alpha
	subps	xmm0, xmm2		; xmm0 = fract(xmm0)
	movaps	xmm3, dqword [SSE_1f]	; xmm3 = 1.0f
	subps	xmm3, xmm0		; xmm3 = 1.0f - xmm0
	; TODO: need movllps xmm3, xmm0!
	movlhps	xmm3, xmm3
	movhlps	xmm0, xmm3		; xmm0 = [1 - fract(min.x), 1 - fract(min.y), fract(max.x), fract(max.y)]
	; get mask
	movlhps	xmm3, xmm2
	movhlps	xmm3, xmm2
	cmpeqps	xmm2, xmm3		; xmm2 = min == max (mask)
	; merge alpha (xmm0) and delta (xmm1) by mask (xmm2)
	xorps	xmm1, xmm0
	andps	xmm1, xmm2
	xorps	xmm0, xmm1
	; get vertices alpha (xmm1) and scale alphas (xmm0, xmm1) up to 255
	movaps	xmm1, xmm0		; xmm1 = xmm0
	shufps	xmm1, xmm1, 10010011b	; xmm1 = xmm0.wxyz
	if defined USE_LAYER_OPACITY
		movss	xmm2, [SSE_MATH + 8]	; xmm2[0] = 128.0f
		shufps	xmm2, xmm2, 0
		;mulps	xmm0, dqword [SSE_128f]	; xmm0 *= 255.0f
	else
		movss	xmm2, [SSE_MATH + 12]	; xmm2[0] = 255.0f
		shufps	xmm2, xmm2, 0
		;mulps	xmm0, dqword [SSE_255f]	; xmm0 *= 255.0f
	end if
	mulps	xmm0, xmm2		; xmm0 *= 255.0f (or 128.0f)
	mulps	xmm1, xmm0		; xmm1 *= xmm0 = [xw, yx, zy, wz] * 255

	movd	xmm2, esi
	shufps	xmm2, xmm2, 0		; xmm2 = [esi, esi, esi, esi]

	cvttps2dq	xmm0, xmm0		; xmm0 = (int)xmm0	(edges alpha)
	cvttps2dq	xmm1, xmm1		; xmm1 = (int)xmm1	(vertices alpha)
	pslld	xmm0, 24
	pslld	xmm1, 24
	por	xmm0, xmm2
	por	xmm1, xmm2
	movaps	[v0], xmm0		; store xmm0 to v0
	movaps	[v1], xmm1		; store xmm1 to v1

	test	eax, eax			; if 1px horizontal (height = 0)
	jz	.hline
	test	ebx, ebx			; if 1px vertical (width = 0)
	jz	.vline

	sub	eax, 2
	sub	ebx, 2
.top:	; span start top-left (alpha)
	PUT_ALPHA_PIXEL [v1.y]
	add	edi, 4
	; span top-center (alpha)
	mov	esi, [v0.y]
	mov	ecx, ebx
	call	Canvas.HLineAlpha
	; span end top-right (alpha)
	PUT_ALPHA_PIXEL [v1.z]
	add	edi, edx

	test	eax, eax
	js	.bottom

	; prepare span start & end alpha coeff
	CANVAS_SET_ALPHA [v0.x],mm1,mm2
	CANVAS_SET_ALPHA [v0.z],mm3,mm4

.mleft:	; span start (alpha)
	CANVAS_SET_PIXELA edi,mm1,mm2
	add	edi, 4

	; span middle-center (opaque)
	test	ebx, ebx
	js	.mright
	mov	ecx, ebx		; ecx = rect.width

	if defined USE_LAYER_OPACITY
		and	esi, 0x00ffffff
		or	esi, 0x5c000000
		call	Canvas.HLineAlpha
	else
	.mcenter:	CANVAS_SET_PIXEL edi,esi	; TODO: memset32_sse
		add	edi, 4		; add offset to next pixel
		dec	ecx
		jnl	.mcenter
	end if

.mright:	; span end (alpha)
	CANVAS_SET_PIXELA edi,mm3,mm4
	add	edi, edx		; add offset to next line
	dec	eax
	jnl	.mleft

.bottom:	; span start bottom-left (alpha)
	PUT_ALPHA_PIXEL [v1.x]
	add	edi, 4
	; span bottom-center (alpha)
	mov	esi, [v0.w]
	mov	ecx, ebx
	call	Canvas.HLineAlpha
	; span end bottom-right (alpha)
	PUT_ALPHA_PIXEL [v1.w]
.done:	ret

.hline:	sub	ebx, 2
	PUT_ALPHA_PIXEL [v1.y]
	add	edi, 4
	mov	esi, [v0.y]
	mov	ecx, ebx
	call	Canvas.HLineAlpha
	PUT_ALPHA_PIXEL [v1.z]
	ret

.vline:	sub	eax, 2
	PUT_ALPHA_PIXEL [v1.y]
	add	edi, edx
	mov	esi, [v0.x]
	mov	ecx, eax
	call	Canvas.VLineAlpha
	PUT_ALPHA_PIXEL [v1.z]
	ret

; in:	xmm0 = [min.xy, max.xy]
;	xmm1 = [width, 0, -width, 0]
Canvas.Line:
	CANVAS_GAMMA_TO_COLOR esi

	shufps	xmm1, xmm1, 01000100b
	movaps	xmm2, xmm0
	subps	xmm0, xmm1
	addps	xmm1, xmm2

	CANVAS_TRANSFORM xmm0
	CANVAS_TRANSFORM xmm1
	CANVAS_CLAMP xmm0
	CANVAS_CLAMP xmm1

	subss	xmm1, xmm0

	xorps	xmm2, xmm2
	movhlps	xmm2, xmm0
	subps	xmm2, xmm0
	movlhps	xmm0, xmm2

	cvttps2dq	xmm0, xmm0
	movaps	[v0], xmm0

	mov	ecx, 4
	; xy delta
	mov	ebx, [v0.w]
	mov	eax, [v0.z]
	or	eax, eax
	;sub	ebx, [v0.y]	; dy
	;sub	eax, [v0.x]	; dx
	jns	@f
	neg	ecx
	neg	eax

; get offset pointer
@@:	cmp	eax, ebx
	jne	.done

	mov	edx, [canvas.width]
	shl	edx, 2
	add	edx, ecx

	;cmp	eax, ebx		; if |dx| >= |dy|
	;jge	.line
	;xchg	eax, ebx		; swap dx, dy
	;xchg	ecx, edx		; swap sx, sy

	;movaps	xmm3, xmm1
	;mulps	xmm1, xcam_scale
	;movaps	xmm3, xmm0
	;movaps	xmm2, xmm0
	;subps	xmm2, xmm1
	;addps	xmm3, xmm1
	;subps	xmm3, xmm2
	;cvttss2si	ebx, xmm3


	cvttss2si	ebx, xmm1
	;jnz	@f
	inc	ebx
;@@:

	;mov	ebx, 1
	mov	ecx, ebx
	shl	ecx, 2
	sub	edx, ecx


.line:	mov	edi, [v0.y]
	imul	edi, [canvas.width]
	add	edi, [v0.x]
	shl	edi, 2
	add	edi, [canvas.bytes]


.loop:	mov	ecx, ebx
	.hline:	CANVAS_SET_PIXEL edi, esi
		add	edi, 4
		dec	ecx
		jnz	.hline

	add	edi, edx

	dec	eax
	jnl	.loop

.done:	ret

; ==== Board ==================================================================
; in:	mouse.pos = current cursor pos
;	mouse.last = last frame cursor pos
Board.View.Move:
	movq	mm0, [mouse.pos]
	psubd	mm0, [mouse.last]
	cvtpi2ps	xmm0, mm0
	movlhps	xmm0, xmm0
	
	divps	xmm0, [board.view.scale]
	addps	xmm0, [board.view.trans]
	movaps	[board.view.trans], xmm0
	call	Window.Repaint
	ret

; in:	eax = zoom value
;	mouse.origin = zoom origin point
Board.View.Zoom:
	; move zoom value to xmm0.x
	cvtsi2ss	xmm0, eax
	mulss	xmm0, [SSE_MATH + 0]	; k = zoom_value * zoom_factor (0.005)
	shufps	xmm0, xmm0, 0		; xmm0 = [k, k, k, k]
	
	; get view params to registers
	movaps	xcam_trans, [board.view.trans]
	movaps	xcam_scale, [board.view.scale]
	
	movaps	xmm1, xcam_scale	; xmm1 = last_scale	
	
	; scale = scale * (1 - zoom * 0.005)
	movaps	xmm2, dqword [SSE_1f]	; xmm2 = 1
	subps	xmm2, xmm0
	mulps	xcam_scale, xmm2
	
	; trans = trans + origin / scale - origin / last_scale
	cvtpi2ps	xmm0, qword [mouse.origin]
	movlhps	xmm0, xmm0		; xmm0 = [origin, origin]
	movaps	xmm2, xmm0		; xmm2 = xmm0
	divps	xmm0, xmm1		; xmm0 = origin / last_scale
	divps	xmm2, xcam_scale		; xmm2 = origin / scale
	addps	xcam_trans, xmm2
	subps	xcam_trans, xmm0

	; update view
	movaps	[board.view.scale], xcam_scale
	movaps	[board.view.trans], xcam_trans
	call	Window.Repaint
	ret

; in:	esi = src memory ptr
;	edi = dst memory ptr
;	ecx = count
;	edx = stride
Board.Load.Layer.Array:
	test	ecx, ecx
	jz	.end

	imul	ecx, edx
	call	System.malloc
	mov	[edi], eax
	mov	edi, eax
	call	System.memcpy_SSE
	add	esi, ecx

.end:	ret

Board.Load.Layer:
	virtual at edi
		.layer	BOARD_LAYER
	end virtual

	push	ecx
	mov	ecx, sizeof.BOARD_LAYER_INFO
	call	System.memcpy_SSE
	add	esi, ecx

	if defined USE_DEBUG
		if defined WINDOWS
			pushad		; TODO: remove pushad/popad
			cinvoke	printf,d_layer_info,[.layer.info.index],[.layer.info.tCount],[.layer.info.pCount]
			popad
		else
			;
		end if
	end if

	push	edi
	mov	edx, sizeof.BOARD_TRACK
	mov	ecx, [.layer.info.tCount]
	lea	edi, [.layer.tracks]
	call	Board.Load.Layer.Array
	pop	edi

	push	edi
	mov	edx, sizeof.BOARD_PAD
	mov	ecx, [.layer.info.pCount]
	lea	edi, [.layer.pads]
	call	Board.Load.Layer.Array
	pop	edi
	pop	ecx

	ret

Board.Load:
	if defined WINDOWS
		struct FILE_DESC
			handle	dd ?
			filesize	dd ?
			fdata	dd ?
		ends
	else
		struct FILE_DESC_XXXXXXX
			freq	FILE_REQ
			finfo	FILE_INFO
			fdata	dd ?
		ends
	end if

	virtual at esp
		.desc	FILE_DESC
	end virtual

	sub	esp, sizeof.FILE_DESC

	; TODO: System.ReadFile -> eax, ecx
	if defined WINDOWS
		; get file size
		invoke	CreateFile,eax,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0
		cmp	eax, INVALID_HANDLE_VALUE
		je	.error
		mov	[.desc.handle], eax
		invoke	GetFileSize,eax,0
		mov	[.desc.filesize], eax
		; allocate memory
		mov	ecx, eax
		call	System.malloc
		mov	[.desc.fdata], eax
		; read file data
		mov	eax, [.desc.handle]
		mov	ebx, [.desc.fdata]
		mov	ecx, [.desc.filesize]
		invoke	ReadFile,eax,ebx,ecx,tmp,0	; layers count
		test	eax, eax
		jz	.error_m
		; close file
		mov	ebx,[.desc.handle]
		invoke	CloseHandle,ebx
	else
		; get file size
		xor	edx, edx
		mov	ecx, 5
		mov	[.desc.freq.arg1], ecx
		mov	[.desc.freq.arg2], edx
		mov	[.desc.freq.arg3], edx
		mov	[.desc.freq.arg4], edx
		lea	ecx, [.desc.finfo]
		mov	[.desc.freq.arg5], ecx
		mov	[.desc.freq.arg6], dl
		mov	[.desc.freq.arg7], eax
		lea	ebx, [.desc.freq]
		mcall	70, ebx

		test	eax, eax
		jnz	.error

		; allocate memory
		mcall	68, 12, [.desc.finfo.filesize]
		mov	[.desc.fdata], eax
		; read file data
		xor	ecx, ecx
		mov	[.desc.freq.arg1], ecx
		mov	ecx, [.desc.finfo.filesize]
		mov	[.desc.freq.arg4], ecx
		mov	ecx, [.desc.fdata]
		mov	[.desc.freq.arg5], ecx

		lea	ebx, [.desc.freq]
		mcall	70, ebx

		test	eax, eax
		jnz	.error_m
	end if

	mov	esi, [.desc.fdata]
	mov	eax, [esi]
	mov	[board.count], eax
	add	esi, 4

	imul	eax, sizeof.BOARD_LAYER
	mov	ecx, eax
	call	System.malloc
	mov	[board.layers], eax

	mov	edi, eax
	mov	ecx, [board.count]

@@:	call	Board.Load.Layer
	add	edi, sizeof.BOARD_LAYER
	dec	ecx
	jnz	@b

	if defined WINDOWS
		mov	eax, [.desc.fdata]
		call	System.free
	else
		mcall	68, 13, [.desc.fdata]
	end if
	add	esp, sizeof.FILE_DESC

	ret

.error_m:	if defined WINDOWS
		mov	eax, [.desc.fdata]
		call	System.free
		invoke	CloseHandle,[.desc.handle]
	else
		mcall	68, 13, [.desc.fdata]
	end if

.error:	mov	[board.count], 0
	if defined USE_DEBUG
		if defined WINDOWS
			cinvoke	printf,e_file
		else
			;
		end if
	end if
	add	esp, sizeof.FILE_DESC
	ret

Board.Render.Layers:
	mov	ecx, [board.count]
	test	ecx, ecx
	jz	.end
	mov	esi, [board.layers]
@@:	push	ecx
	push	esi
	call	Board.Render.Layer
	pop	esi
	pop	ecx
	add	esi, sizeof.BOARD_LAYER
	dec	ecx
	jnz	@b
.end:	call	Board.Render.Grid
	ret

Board.Render.Layer:
	virtual at esi
		.layer	BOARD_LAYER
	end virtual

.tracks:	mov	eax, Board.Render.Layer.Track
	mov	ebx, [.layer.tracks]
	mov	ecx, [.layer.info.tCount]
	mov	edx, sizeof.BOARD_TRACK
	call	Board.Render.Primitive

.pads:	mov	eax, Board.Render.Layer.Pad
	mov	ebx, [.layer.pads]
	mov	ecx, [.layer.info.pCount]
	mov	edx, sizeof.BOARD_PAD
	call	Board.Render.Primitive
	ret

; in:	eax = render procedure
;	ebx = pointer to array
;	ecx = count
;	edx = stride
Board.Render.Primitive:
	test	ecx, ecx
	jz	.done

	push	edx	; move to [esp]

@@:	push	eax
	push	ebx
	push	ecx
	push	esi

	call	eax

	pop	esi
	pop	ecx
	pop	ebx
	pop	eax

	add	ebx, [esp]
	dec	ecx
	jnz	@b

	pop	edx
.done:	ret

Board.Render.Layer.Track:
	virtual at esi
		.layer	BOARD_LAYER
	end virtual

	virtual at ebx
		.track	BOARD_TRACK
	end virtual

	xorps	xmm2, xmm2
	movaps	xmm0, dqword [.track.pos1]	; xmm0 = [pos2.yx, pos1.yx]
	movss	xmm1, [.track.w]		; xmm1 = [0, 0, 0, w]
	movlhps	xmm2, xmm1		; xmm2 = [0, w, 0, 0]
	subps	xmm1, xmm2		; xmm1 = [0, -w, 0, w]
	mov	esi, [.layer.info.color]

	mov	eax, [.track.pos1.x]
	cmp	eax, [.track.pos2.x]	; pos1.x = pos2.x
	je	.vline
	mov	eax, [.track.pos1.y]
	cmp	eax, [.track.pos2.y]	; pos1.x = pos2.x
	je	.hline
	mulss	xmm1, [SSE_MATH_EX]
	call	Canvas.Line
	jmp	.done

.vline:	shufps	xmm1, xmm1, 01000110b	; xmm1 = [0, w, 0, -w]
 	jmp	.line
.hline:	shufps	xmm1, xmm1, 00011001b	; xmm1 = [w, 0, -w, 0]
.line:	call	Canvas.Fill
.done:	ret

Board.Render.Layer.Pad:
	virtual at esi
		.layer	BOARD_LAYER
	end virtual

	virtual at ebx
		.pad	BOARD_PAD
	end virtual

	movq	xmm0, [.pad.pos]
	movq	xmm2, [.pad.size]
	xorps	xmm1, xmm1
	subps	xmm1, xmm2
	movlhps	xmm1, xmm2	; xmm1 = [-size, +size]
	movlhps	xmm0, xmm0
	push	ebx
	mov	esi, [.layer.info.color]
	call	Canvas.Fill
	pop	ebx

	mov	eax, [.pad.hole.x]
	or	eax, [.pad.hole.y]
	jz	.done

	movq	xmm0, [.pad.pos]
	movq	xmm2, [.pad.hole]
	xorps	xmm1, xmm1
	subps	xmm1, xmm2
	movlhps	xmm1, xmm2	; xmm1 = [-size, +size]
	movlhps	xmm0, xmm0
	mov	esi, COLOR_SMT_HOLE
	test	[.pad.flags], PAD_FLAG_THT
	jz	@f
	mov	esi, COLOR_THT_HOLE
@@:	call	Canvas.Fill
.done:	ret

Board.Render.Grid:
	mov	esi, 0xffffff
	CANVAS_GAMMA_TO_COLOR esi
	movaps	xmm0, xcam_trans
	movd	xmm2, [SSE_MATH + 12]
	shufps	xmm2, xmm2, 0

	mov	ecx, 100
@@:	addps	xmm0, xmm2
	call	Canvas.Dot
	dec	ecx
	jnz	@b

	ret
; ==== DATA ===================================================================
	if defined USE_DEBUG
		d_fps		db 'FPS: %d',10,0
		d_count		db '%d ',0
		d_view		db '%d %d %d',10,0
		d_layer_info	db '- layer: %d',9,'tracks: %d',9,'pads: %d',10,0
		e_file		db 'file not found',10,0
	end if

	m_file			db 'File',0
	m_file_new		db 'New',9,'Ctrl+N',0
	m_file_open		db 'Open...',9,'Ctrl+O',0
	m_file_save		db 'Save',9,'Ctrl+S',0
	m_file_save_as		db 'Save As...',9,'Ctrl+Alt+S',0
	m_file_exit		db 'Exit',9,'Alt+F4',0
	
	m_edit			db 'Edit',0
	m_edit_undo		db 'Undo',9,'Ctrl+Z',0
	m_edit_redo		db 'Redo',9,'Ctrl+Y',0
	m_edit_cut		db 'Cut',9,'Ctrl+X',0
	m_edit_copy		db 'Copy',9,'Ctrl+C',0
	m_edit_paste		db 'Paste',9,'Ctrl+V',0
	m_edit_delete		db 'Delete',9,'DEL',0
	m_edit_select_all		db 'Select All',9,'Ctrl+A',0
	;m_edit_rotate		db 'Rotate',9,'Spacebar',0
	
	m_view			db 'View',0
	m_view_flip		db 'Flip',9,'Ctrl+F',0
	
	m_tools			db 'Tools',0
	m_tools_track		db 'Track',9,'T',0
	m_tools_pad		db 'Pad',9,'P',0
	m_tools_region		db 'Region',9,'R',0
	m_tools_component		db 'Component',9,'C',0
		
	m_tools_measure		db 'Measure',0
	m_tools_measure_linear	db 'Linear',9,'Ctrl+Alt+L',0
	m_tools_measure_angular	db 'Angular',9,'Ctrl+Alt+A',0
	
	if defined WINDOWS
		WND_CLASS		db 'static',0
		;filename		db 'ECAD.epr',0
		;filename		db 'DB46.epr',0
		;filename		db 'Rhino.epr',0
		filename		db 'huge.epr',0
		
		HOTKEYS	db	FCONTROL, 'N',\		; MC_FILE_NEW
				FCONTROL, 'O',\		; MC_FILE_OPEN
				FCONTROL, 'S',\		; MC_FILE_SAVE
				FCONTROL + FALT, 'S',\	; MC_FILE_SAVE_AS
				FALT, VK_F4,\		; MC_FILE_EXIT
				FCONTROL, 'Z',\		; MC_EDIT_UNDO
				FCONTROL, 'Y',\		; MC_EDIT_REDO
				FCONTROL, 'X',\		; MC_EDIT_CUT
				FCONTROL, 'C',\		; MC_EDIT_COPY
				FCONTROL, 'V',\		; MC_EDIT_PASTE
				0, VK_DELETE,\		; MC_EDIT_DELETE
				FCONTROL, 'A',\		; MC_EDIT_SELECT_ALL
				FCONTROL, 'F',\		; MC_VIEW_FLIP
				0, 'T',\			; MC_TOOLS_TRACK
				0, 'P',\			; MC_TOOLS_PAD
				0, 'R',\			; MC_TOOLS_REGION
				0, 'C',\			; MC_TOOLS_COMPONENT
				FCONTROL + FALT, 'L',\	; MC_TOOLS_MEASURE_LINEAR
				FCONTROL + FALT, 'A'	; MC_TOOLS_MEASURE_ANGULAR
		
		;ACCEL_LIST dw	FVIRTKEY or FCONTROL, 'N', MC_FILE_NEW,\
		;		FVIRTKEY or FCONTROL, 'O', MC_FILE_OPEN,\
		;		FVIRTKEY or FCONTROL, 'S', MC_FILE_SAVE,\
		;		FVIRTKEY or FCONTROL or FALT, 'S', MC_FILE_SAVE_AS,\
		;		FVIRTKEY or FALT, VK_F4, MC_FILE_EXIT,\
		;		FVIRTKEY or FCONTROL, 'Z', MC_EDIT_UNDO,\
		;		FVIRTKEY or FCONTROL, 'Y', MC_EDIT_REDO,\
		;		FVIRTKEY or FCONTROL, 'X', MC_EDIT_CUT,\
		;		FVIRTKEY or FCONTROL, 'C', MC_EDIT_COPY,\
		;		FVIRTKEY or FCONTROL, 'V', MC_EDIT_PASTE,\
		;		FVIRTKEY, VK_DELETE, MC_EDIT_DELETE,\
		;		FVIRTKEY or FCONTROL, 'A', MC_EDIT_SELECT_ALL,\
		;		FVIRTKEY or FCONTROL, 'F', MC_VIEW_FLIP,\
		;		FVIRTKEY, 'T', MC_TOOLS_TRACK,\
		;		FVIRTKEY, 'P', MC_TOOLS_PAD,\
		;		FVIRTKEY, 'R', MC_TOOLS_REGION,\
		;		FVIRTKEY, 'C', MC_TOOLS_COMPONENT,\
		;		FVIRTKEY or FCONTROL or FALT, 'L', MC_TOOLS_MEASURE_LINEAR,\
		;		FVIRTKEY or FCONTROL or FALT, 'A', MC_TOOLS_MEASURE_ANGULAR				
	else
		filename		db '/tmp0/1/huge.epr',0
	end if
	WND_TITLE		db 'ECAD',0

; aligned data -------------------------------
align 16
I_END:	SSE_MATH		dd 0.005f, 1.0f, 192.0f, 255.0f
	SSE_1f		dd 1.0f, 1.0f, 1.0f, 1.0f
	SSE_MATH_EX	dd 1.4142135, 0.0, 0.0, 0.0
	SSE_SIGN_MASK	dd 0, 0x80000000, 0, 0x80000000

	; ECAD
	;cam_trans		dd -14335825.0f, 5295986.0f, 0.0f, 0.0f
	;cam_scale		dd 56288.0f, 0.0f, 0.0f, 0.0f
	; DB46
	;cam_trans		dd -28178378.0f, -40215676.0f, 0.0f, 0.0f
	;cam_scale		dd 49000.0f, 0.0f, 0.0f, 0.0f
	; Rhino
	;cam_trans		dd -104608432.0f, -171654368.0f, 0.0f, 0.0f
	;cam_scale		dd 171392.0f, 0.0f, 0.0f, 0.0f
	; huge
	cam_trans		dd -104608432.0f, -267510368.0f, 0.0f, 0.0f
	cam_scale		dd 171392.0f, 0.0f, 0.0f, 0.0f

	v0		VEC4	; temp aligned 128-bit variable
	v1		VEC4	; temp aligned 128-bit variable

	canvas		CANVAS

; non-aligned data ---------------------------
	board		BOARD

	if defined WINDOWS
		sys_heap		dd ?
		hwnd		dd ?
		hmenu		dd ?
		haccel		dd ?
		msg		MSG
		bmi		BITMAPINFOHEADER
	else
		proc_info	process_information
		blit_info	BLIT_INFO
	end if
	mouse		MOUSE
	tmp		dd ?
	if defined USE_DEBUG
		fps		dd ?
		frame		dd ?
		frame_time	dd ?
	end if

	if defined USE_GAMMA_CORRECTION
		LUT_color2gamma:	rb 256
		LUT_gamma2color:	rb 256
	end if
align 16
IM_END: