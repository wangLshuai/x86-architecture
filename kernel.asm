
core_code_seg_sel   equ 0x38
core_data_seg_sel   equ 0x30
sys_routine_seg_sel equ 0x28
core_stack_seg_sel  equ 0x20
mem_0_4_gb_seg_sel  equ 0x18
video_ram_seg_sel   equ 0x10



core_length dd core_end  ;0x00

sys_routine_seg dd section.sys_routine.start ;0x04
core_data_seg dd section.core_data.start        ;0x08
core_code_seg dd section.core_code.start  ;汇编地址 ,0x0c
core_entry  dd start        ;段内偏移,0x10
            dw core_code_seg_sel  ;段选择子 ,0x38

[bits 32]
SECTION sys_routine vstart=0
put_string:         ;输入ds:ebx 字符串
    push ecx
.getc:
    mov cl,[ebx]
    or cl,cl
    jz .exit
    call put_char ;cl 不为0
    inc ebx
    jmp .getc
.exit:
    pop ecx
    retf

put_char:          ;输入cl为字符
    pushad          ;压栈 eax ecx edx ebx esp ebp esi edi, popad 按顺序出栈

    ;当前光标位置
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    inc dx
    in al,dx
    mov ah,al  ;保存光标高位

    dec dx
    mov al,0x0f
    out dx,al
    inc dx
    in al,dx
    mov bx,ax

    cmp cl,0x0d ;?回车符
    jnz .put_0a
    mov ax,bx
    mov bl,80
    div bl  ;ax = ax/80
    mul bl  ;ax=ax*80,当前行首位置
    mov bx,ax
    jmp .set_cursor

.put_0a:
    cmp cl,0x0a     ;换行符
    jnz .put_other
    add bx,80
    jmp .roll_screen

.put_other:          ;可打印字符
    push es
    mov eax,video_ram_seg_sel
    mov es,ax
    shl bx,1
    mov [es:bx],cl
    pop es

    shr bx,1
    inc bx

.roll_screen:
    cmp bx,2000
    jl .set_cursor

    push ds
    push es
    push ebx
    mov eax,video_ram_seg_sel
    mov ds,eax
    mov es,eax
    cld
    mov esi,0xa0
    mov edi,0x00
    mov ecx,1920
    rep movsw
    mov bx,3840
    mov ecx,80
.cls:
    mov word[es:bx],0x0720
    add bx,2
    loop .cls

    pop ebx
    pop es
    pop ds
    sub bx,80

.set_cursor:
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    inc dx
    mov al,bh
    out dx,al
    dec dx
    mov al,0x0f
    out dx,al
    inc dx
    mov al,bl
    out dx,al

    popad
    ret


SECTION core_data vstart=0

hello_msg: db 'boot kernel',0x0a,0x0a,0x0a,0x0a,0x0a,0x0a
db 0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0x0a,0
hello_msg_end:

SECTION core_code vstart=0

start:
    push ds
    push es
    push eax
    push ebx
    push ecx

    mov ax,core_data_seg_sel
    mov ds,ax

    mov ebx,hello_msg
    call sys_routine_seg_sel:put_string


    pop ecx
    pop ebx
    pop eax
    pop es
    pop ds
    retf

SECTION core_trail
core_end: