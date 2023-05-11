SECTION header vstart=0
program_length:
    dd program_end
code_entry:
    dw start ;[0x04]
    dd section.code_1.start ;[0x06]
realloc_tbl_len:
    dw (header_end-code_1_segment)/4 ;[0x0a]


code_1_segment dd section.code_1.start ;[0x0c]
code_2_segment dd section.code_2.start ;[0x10]
data_1_segment dd section.data_1.start
data_2_segment dd section.data_2.start
stack_segment  dd section.stack.start

header_end:


SECTION code_1 align=16 vstart=0
put_string:
    mov cl,[bx]
    or cl,cl
    jz .exit   ;[bx] 为0退出过程
    call put_char
    inc bx
    jmp put_string

    .exit:
    ret
; 显示一个字符，cl ascii
put_char:
    push ax
    push bx
    push cx
    push dx
    push ds
    push es

;光标位置 高8位
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    mov dx,0x3d5
    in al,dx
    mov ah,al
;低8位
    mov dx,0x3d4
    mov al,0x0f
    out dx,al
    mov dx,0x3d5
    in al,dx
    mov bx,ax

    cmp cl,0x0d  ;回车符?
    jnz .put_0a  ;不是
    mov ax,bx    ;bx 是光标位置 小于25*80
    mov bl,80
    div bl       ;ax = ax/bl ;结果小于25，小于256，高字节为0
    mul bl       ;ax = al*bl
    mov bx,ax    ;ax = ax/80 *80
    jmp .set_cursor

.put_0a:
    cmp cl,0x0a ;换行符
    jnz .put_other ;不是
    add bx,80
    jmp .roll_screen

.put_other:
    mov ax,0xb800
    mov es,ax
    shl bx,1
    mov [es:bx],cl

    shr bx,1
    add bx,1

.roll_screen:
    cmp bx,2000 ;光标超出屏幕？
    jl .set_cursor 

    mov ax,0xb800
    mov ds,ax
    mov es,ax
    cld
    mov si,0xa0
    mov di,0x00
    mov cx,1920
    rep movsw
    push bx
    mov bx,3840
    mov cx,80
.cls:
    mov word [es:bx],0x0720
    add bx,2
    loop .cls
    pop bx
    sub bx,80
.set_cursor:
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    mov dx,0x3d5
    mov al,bh
    out dx,al
    mov dx,0x3d4
    mov al,0x0f
    out dx,al
    mov dx,0x3d5
    mov al,bl
    out dx,al

    pop es
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax
    ret

start:
    mov ax,[stack_segment]
    mov ss,ax
    mov sp,stack_end

    mov ax,[data_1_segment]
    mov ds,ax

    mov bx,msg0  ;ds:bx是string地址 
    call put_string
    
    mov ax, [es:code_2_segment]   ;code2 在内存中的段地址
    mov [es:code_2_segment+2],ax
    mov word [es:code_2_segment],begin
    call far [es:code_2_segment]

    retf    ;自动pop ip pop cs
continue:
    mov ax, [es:data_2_segment]
    mov ds,ax
    mov bx,msg1
    call put_string

    retf


SECTION code_2 align=16 vstart=0

    begin:
        push word [es:code_1_segment]
        mov ax,continue
        push ax
        retf   ;pop ip pop cs ; code_1_segment:continue
SECTION data_1 align=16 vstart=0

    msg0 db ' This is NASM - the famous Netwide Assembler. '
         db 'Back at SourceForge and in intensive development! '
         db 'Get the current versions from http://www.nasmi.us/.'
         db 0x0d,0x0a,0x0d,0x0a
         db ' Example code fro cacluate 1+2+...+1000:',0x0d,0x0d,0x0a
         db ' xor dx,dx',0x0d,0x0a
         db ' xor ax,ax',0x0d,0x0a
         db ' xor cx,cx',0x0d,0x0a
         db ' @@:',0x0d,0x0a
         db '   inc cx',0x0d,0x0a
         db '   add ax,cx',0x0d,0x0a
         db '   adc dx,0',0x0d,0x0a
         db '   cmp cx,1000',0x0d,0x0a
         db '   jle @@',0x0d,0x0a
         db '   ... ...       (Some other codes)',0x0a,0x0a,0x0a,0x0a
         db 0
    
SECTION data_2 align=16 vstart=0
    msg1 db '  The above contents is written by leechung.'
         db '20230513',0x0a,0x0a
        
SECTION stack align=16 vstart=0
    resb 256 ;
stack_end:


SECTION trail align=16
program_end:



