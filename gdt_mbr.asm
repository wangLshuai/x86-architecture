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

;第一个段描述符，代码段
add bx,8
mov dword [bx],0x7c0001ff
mov dword [bx+4],0x00409800 ;段基址0x7c00,界限0x1ff,1字节粒度，32位操作尺度，段存在，0特权级别，代码段或数据段，只执行。

;第2个段描述符
mov ax,3999    ;段界限,显存段界限
add bx,8
mov word [bx],ax ;15-0

;显存段 0xb800 0xb8000
mov word [bx+2],0x8000

mov byte [bx+4],0x0b
xor al,al
or al,0x02 ;低4位是type xewa ,读写
or al,10010000b ;高四位设置段存在 特权0 数据段
mov byte [bx+5],al
xor al,al  ;低4位是段界限 16-19
or al,01000000b ;高四位GBL(AVL)设置 粒度为字节,32位栈偏移寄存器esp,
mov byte [bx+6],al
mov byte [bx+7],0 ;段基址的24-31

;3数据段 0-4G
add bx,8
mov dword [bx],0x0000ffff ;基地址0,界限fffff，32位尺寸，可读写，向下扩展数据段
mov dword [bx+4],0x00cf9200

;栈段4 ss = 4<<3
add bx,8
mov dword [bx],0x7c00fffe ;基地址0x7c00，界限0xffffe,4K,读写向下段，32位操作操作尺寸。下届是0x7c00+0xffffe*4k，上界是0x7c00+0xffffffff.下届是0x7c00+(0xffffffff-0xfffe*4k)=0x7c00+0xffffe000
mov dword [bx+4],0x00cf9600

mov word [cs:gdt_size+0x7c00],39 ;gdtr 48位，高32位是gdt表起始地址，低16位是gdt边界。两个描述符，5*8-1
lgdt [cs:0x7c00+gdt_size]

; 打开20号地址线
in al,0x92
or al,0000_0010B
out 0x92,al

cli  ;保护模式下中断未建立，禁止中断

mov eax,cr0
or eax,0x01
mov cr0,eax  ;使能保护模式;此时代码还使用实模式cs生成的在告诉描述符缓冲里的段描述符

jmp dword 0x0008:flush
[bits 32]
flush:
    mov ax,1
    shl ax,4
    mov ds,ax   ;刷新ds的高速短描述符缓冲，数据段基址使用了gdt中的段描述符

    mov ax,32
    mov ss,ax
    xor esp,esp ;向下增长的栈段

    mov byte [0x00],'P'  
    mov byte [0x02],'r'
    mov byte [0x04],'o'
    mov byte [0x06],'t'
    mov byte [0x08],'e'
    mov byte [0x0a],'c'
    mov byte [0x0c],'t'
    mov byte [0x0e],' '
    mov byte [0x10],'m'

    mov byte [0x12],'o'
    mov byte [0x14],'d'
    mov byte [0x16],'e'
    mov byte [0x18],' '
    mov byte [0x1a],'O'
    mov byte [0x1c],'K'

    mov eax,24
    mov ds,eax  ;第三个段，代码段的别名，可读写
    mov eax,16
    mov es,eax
    mov ecx,gdt_size-string
    xor ebx,ebx
L1:
    mov byte dx,[ebx+string+0x7c00]
    mov byte [es:160+ebx*2],dl
    inc ebx
    loop L1


    ;【sp】 位计数exc 【sp+4】最大字符的索引,【sp+6】,最大字符的值
    sub esp,8
    mov ecx,gdt_size-string-1
for1 
    mov byte ax,[string+0x7c00]  ;第一个字符最大
    mov [esp+6],al       
    mov word [esp+4],0         ;最大字符索引
    mov [esp],ecx         

    xor bx,bx   ;循环ecx 次，bx 是0-ecx-1
for2:
    mov byte eax,[string+0x7c00+bx]
    mov byte edx,[esp+6]
    cmp al,dl
    jna L2
    mov byte [esp+6],al ;字符大于缓存的，记录字符的值和字符的索引
    mov [esp+4],bx
L2:
    inc bx
    loop for2

    mov ecx,[esp]
    mov bx,[esp+4]
    mov byte eax,[string+0x7c00+ecx-1]
    xchg [string+0x7c00+bx],al
    mov [string+0x7c00+ecx-1],al
    loop for1

    xor ebx,ebx
    mov ecx,gdt_size-string
L3:
    mov byte dx,[ebx+string+0x7c00]
    mov byte [es:320+ebx*2],dl
    inc ebx
    loop L3
    
idle:
    hlt
    jmp idle

string db 's0ke4or92xap3fv8giuzjcy5l1m7hd6bnqtw.'


gdt_size: dw 0
gdt_base: dd 0x00007e00

times 510-($-$$) db 0
db 0x55,0xaa