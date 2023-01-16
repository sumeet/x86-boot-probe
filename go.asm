[bits 16]
[org 0x7c00]

%define FUNCTION_TTY 0x0e
%define INT_VIDEO 0x10
%define CR4_FLAGS 0b11000

%define FREE_SPACE 0x9000

%macro print_real_mode 1
	mov ah, FUNCTION_TTY
	mov si, %1
%%print_char:
	lodsb
	cmp al, 0
	je %%done
	int INT_VIDEO
	jmp %%print_char
%%done:
%endmacro

%macro set_cursor 2
VGA.Width equ 80
%%SetCoords:
; input %1 = x, %2 = y
; modifies ax, bx, dx
 
	mov dl, VGA.Width
	mul dl
	mov bx, %1
	add bx, %2
 
%%SetOffset:
; input bx = cursor offset
; modifies al, dx
 
	mov dx, 0x03D4
	mov al, 0x0F
	out dx, al
 
	inc dl
	mov al, bl
	out dx, al
 
	dec dl
	mov al, 0x0E
	out dx, al
 
	inc dl
	mov al, bh
	out dx, al
%endmacro

load:
  xor ax, ax    ; make sure ds is set to 0
  mov ds, ax
  cld
  ; start putting in values:
  mov ah, 2h    ; int13h function 2
  mov al, 63    ; we want to read 63 sectors
  mov ch, 0     ; from cylinder number 0
  mov cl, 2     ; the sector number 2 - second sector (starts from 1, not 0)
  mov dh, 0     ; head number 0
  xor bx, bx    
  mov es, bx    ; es should be 0
  mov bx, stage2 ; 512bytes from origin address 7c00h
  int 13h


	xor ax, ax
	mov ss, ax
	mov sp, load
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    cld

	mov edi, FREE_SPACE

	jmp SwitchToLongMode     ; jump to the next sector

padding: times 510-($-$$) db 0x00a
dw 0xaa55

stage2:
%define PAGE_PRESENT    (1 << 0)
%define PAGE_WRITE      (1 << 1)
 
%define CODE_SEG     0x0008
%define DATA_SEG     0x0010
 
ALIGN 4
IDT:
    .Length       dw 0
    .Base         dd 0
 
; Function to switch directly to long mode from real mode.
; Identity maps the first 2MiB.
; Uses Intel syntax.
 
; es:edi    Should point to a valid page-aligned 16KiB buffer, for the PML4, PDPT, PD and a PT.
; ss:esp    Should point to memory that can be used as a small (1 uint32_t) stack
 
SwitchToLongMode:
    ; Zero out the 16KiB buffer.
    ; Since we are doing a rep stosd, count should be bytes/4.   
    push di                           ; REP STOSD alters DI.
    mov ecx, 0x1000
    xor eax, eax
    cld
    rep stosd
    pop di                            ; Get DI back.
 
 
    ; Build the Page Map Level 4.
    ; es:di points to the Page Map Level 4 table.
    lea eax, [es:di + 0x1000]         ; Put the address of the Page Directory Pointer Table in to EAX.
    or eax, PAGE_PRESENT | PAGE_WRITE ; Or EAX with the flags - present flag, writable flag.
    mov [es:di], eax                  ; Store the value of EAX as the first PML4E.
 
 
    ; Build the Page Directory Pointer Table.
    lea eax, [es:di + 0x2000]         ; Put the address of the Page Directory in to EAX.
    or eax, PAGE_PRESENT | PAGE_WRITE ; Or EAX with the flags - present flag, writable flag.
    mov [es:di + 0x1000], eax         ; Store the value of EAX as the first PDPTE.
 
 
    ; Build the Page Directory.
    lea eax, [es:di + 0x3000]         ; Put the address of the Page Table in to EAX.
    or eax, PAGE_PRESENT | PAGE_WRITE ; Or EAX with the flags - present flag, writeable flag.
    mov [es:di + 0x2000], eax         ; Store to value of EAX as the first PDE.
 
 
    push di                           ; Save DI for the time being.
    lea di, [di + 0x3000]             ; Point DI to the page table.
    mov eax, PAGE_PRESENT | PAGE_WRITE    ; Move the flags into EAX - and point it to 0x0000.
 
 
    ; Build the Page Table.
.LoopPageTable:
    mov [es:di], eax
    add eax, 0x1000
    add di, 8
    cmp eax, 0x200000                 ; If we did all 2MiB, end.
    jb .LoopPageTable
 
    pop di                            ; Restore DI.
 
    ; Disable IRQs
    mov al, 0xFF                      ; Out 0xFF to 0xA1 and 0x21 to disable all IRQs.
    out 0xA1, al
    out 0x21, al
 
    nop
    nop
 
    lidt [IDT]                        ; Load a zero length IDT so that any NMI causes a triple fault.
 
    ; Enter long mode.
    mov eax, 10100000b                ; Set the PAE and PGE bit.
    mov cr4, eax
 
    mov edx, edi                      ; Point CR3 at the PML4.
    mov cr3, edx
 
    mov ecx, 0xC0000080               ; Read from the EFER MSR. 
    rdmsr    
 
    or eax, 0x00000100                ; Set the LME bit.
    wrmsr
 
    mov ebx, cr0                      ; Activate long mode -
    or ebx,0x80000001                 ; - by enabling paging and protection simultaneously.
    mov cr0, ebx                    
 
    lgdt [GDT.Pointer]                ; Load GDT.Pointer defined below.
 
    jmp CODE_SEG:LongMode             ; Load CS with 64 bit segment and flush the instruction cache
 
 
    ; Global Descriptor Table
GDT:
.Null:
	dq 0x0000000000000000             ; Null Descriptor - should be present.
 
.Code:
    dq 0x00209A0000000000             ; 64-bit code descriptor (exec/read).
    dq 0x0000920000000000             ; 64-bit data descriptor (read/write).
 
ALIGN 4
    dw 0                              ; Padding to make the "address of the GDT" field aligned on a 4-byte boundary
 
.Pointer:
    dw $ - GDT - 1                    ; 16-bit Size (Limit) of GDT.
    dd GDT                            ; 32-bit Base Address of GDT. (CPU will zero extend to 64-bit)
 
 
[BITS 64]      
LongMode:
    mov ax, DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
 
    ; Blank out the screen to a blue color.
	mov edi, 0xB8000
    mov rcx, 500                      ; Since we are clearing uint64_t over here, we put the count as Count/4.
    mov rax, 0x1F201F201F201F20       ; Set the value to set the screen to: Blue background, white foreground, blank spaces.
    rep stosq                         ; Clear the entire screen. 
 main:
	set_cursor 0, 0
	
	mov rsi, msg4
	mov rdi, 0x1F
	call write_string

	mov rsi, 1337
	mov rdi, print_buf
	call writei

	mov rsi, print_buf
	mov rdi, 0x1F
	call write_string	
halt:
	hlt
	jmp main

msg: db "hello", 13, 10, 0
msg2: db "set up page tables", 13, 10, 0
msg3: db "entered compatibility mode", 13, 10, 0
msg4: db "we're in x86_64 ", 0
cursor: dd 0xb8000
print_buf: times 512 db 0

writei:
        mov     rcx, rdi
        mov     rax, rsi
        mov     edi, 10
        xor     esi, esi
.L2:
        test    rax, rax
        jle     .L7
        cqo
        idiv    rdi
        add     edx, 48
        mov     BYTE [rcx+rsi], dl
        inc     rsi
        jmp     .L2
.L7:
        mov     rdx, rsi
        mov     rdi, rsi
        sub     rdx, rax
        shr     rdi, 1
        add     rdx, rcx
.L4:
        dec     rdx
        cmp     rax, rdi
        jnb     .L8
        mov     r8b, BYTE [rcx+rax]
        mov     r9b, BYTE [rdx]
        mov     BYTE [rcx+rax], r9b
        inc     rax
        mov     BYTE [rdx], r8b
        jmp     .L4
.L8:
        mov     BYTE [rcx+rsi], 0
        ret

write_string:
        mov     eax, dword [cursor]
.L2:
        mov     dl, BYTE [rsi]
        test    dl, dl
        je      .L5
        mov     BYTE [rax], dl
        inc     rsi
		inc     dword [cursor]
		inc     dword [cursor]
        add     rax, 2
        mov     BYTE [rax-1], dil
        jmp     .L2
.L5:
        ret

