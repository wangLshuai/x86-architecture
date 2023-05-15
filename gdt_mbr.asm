mov ax,cs
mov ss,ax
mov sp,0x7c00

;gdt_base是汇编地址，加上段起始内存地址则得到她的内存段偏移地址
mov ax,[cs:gdt_base+0x7c00]
mov dx,[cs:gdt_base+0x7c00+2]

mov bx,16
div bx
push ds
mov ds,ax

mov bx,dx
mov dword [bx],0x00   
mov dword [bx+4],0x00 ;0段描述符为null

;第一个段描述符
mov ax,3999    ;段界限,显存段界限

mov word [bx+8],ax ;15-0

;显存段 0xb800 0xb8000
mov word [bx+10],0x8000

mov byte [bx+12],0x0b

xor al,al
or al,0x02 ;低4位是type xewa ,读写
or al,10010000b ;高四位设置段存在 特权0 数据段
mov byte [bx+13],al

xor al,al  ;低4位是段界限 16-19
or al,01000000b ;高四位GBL(AVL)设置 粒度为字节,32位栈偏移寄存器esp,
mov byte [bx+14],al

mov byte [bx+15],0 ;段基址的24-31

mov word [cs:gdt_size+0x7c00],15 ;gdtr 48位，高32位是gdt表起始地址，低16位是gdt边界。两个描述符，2*8-1
lgdt [cs:0x7c00+gdt_size]

; 打开20号地址线
in al,0x92
or al,0000_0010B
out 0x92,al

cli  ;保护模式下中断未建立，禁止中断

mov eax,cr0
or eax,0x01
mov cr0,eax  ;使能保护模式;此时代码还使用实模式cs生成的在告诉描述符缓冲里的段描述符

mov ax,1
shl ax,3
mov ds,ax   ;刷新ds的高速短描述符缓冲，数据段基址使用了gdt中的段描述符

mov bx,0
mov byte [bx],'a'

.idle:
    hlt
    jmp .idle

;得到光标












gdt_size: dw 0
gdt_base: dd 0x00007e00

times 510-($-$$) db 0
db 0x55,0xaa