core_base_address equ 0x00040000  ;内核加载地址,第252k
core_start_sector equ 0x00000001  ;内核在硬盘上第1扇区
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
    mov ax,32
    mov ss,ax
    xor esp,esp ;向下增长的栈段

    mov eax,0x0018 ;数据段3
    mov ds,ax

    mov edi,core_base_address
    mov eax,core_start_sector
    mov ebx,edi
    call read_hard_disk_0

    mov eax,[edi]   ;core_length
    xor edx,edx
    mov ecx,512
    div ecx

    or edx,edx
    jnz @1     ;edx 1=0 ,有余数 ，跳转
    dec eax
@1:
    or eax,eax
    jz setup    ;eax 为0，不需要继续读

    ;读剩余扇区
    mov ecx,eax
    mov eax,core_start_sector
    inc eax
@2:
    call read_hard_disk_0
    inc eax
    loop @2

setup:
    mov esi,[0x7c00+gdt_base]        ;gdt

    ;建立公用例程段描述符
    mov eax,[edi+0x04]  ;公用例程段汇编地址
    mov ebx,[edi+0x08]  ;core_data_seg 汇编地址
    sub ebx,eax
    dec ebx             ;公用例程段界限
    add eax,edi         ;公用例程段内存地址
    mov ecx,0x00409800  ;32位尺度，p存在，0特权级别，s数据段或代码段,只执行代码段
    call make_gdt_descriptor
    mov [esi+5*8],eax   ;第5个描述符
    mov [esi+5*8+4],edx

    ;建立内核数据段描述符
    mov eax,[edi+0x08]
    mov ebx,[edi+0x0c]
    sub ebx,eax         ;段长度
    dec ebx
    add eax,edi
    mov ecx,0x00409200
    call make_gdt_descriptor
    mov [esi+6*8],eax
    mov [esi+6*8+4],edx

    ;建立core_code代码段描述符
    mov eax,[edi+0x0c]
    mov ebx,[edi]
    sub ebx,eax         ;core_code长度
    dec ebx             ;界限
    add eax,edi
    mov ecx,0x00409800
    call make_gdt_descriptor
    mov [esi+7*8],eax
    mov [esi+7*8+4],edx

    mov word [0x7c00+gdt_size],8*8-1
    lgdt [0x7c00+gdt_size]
    call far [edi+0x10]
idle:
    hlt
    jmp idle

read_hard_disk_0:  ;从主硬盘读取一个逻辑扇区 输入EAX:为硬盘逻辑扇区，DS:EBX内存缓冲区，返回：EBX=EBX+512
    push eax
    push ecx
    push edx

    push eax
    mov dx,0x1f2
    mov al,1
    out dx,al        ;操作一个扇区

    inc dx          ;0x1f3
    pop eax
    out dx,al       ;LBA 地址7-0,总共有28位逻辑扇区编号

    inc dx          ;0x1f4
    shr eax,8       
    out dx,al       ;LBA 8-15


    inc dx          ;0x1f5
    shr eax,8
    out dx,al       ;LBA 16-23

    inc dx          ;0x1f6
    shr eax,8
    or al,0xe0      ; LBA28模式，主盘。LBA 24-27位

    inc dx          ;0x1f7
    mov al,0x20
    out dx,al       ;读取命令

.waits:
    in al,dx
    and al,0x88
    cmp al,0x08
    jnz .waits       ;不相等则忙碌，等待数据准备好

    mov ecx,256
    mov dx,0x1f0    ;硬盘io输入端口号

.readw:
    in ax,dx
    mov [ebx],ax
    add ebx,2
    loop .readw

    pop edx
    pop ecx
    pop eax
    ret

make_gdt_descriptor:       ;输入EAX 线性地址，段的基地址，EBX 界限，ECX属性，返回EDX:EAX 段描述符
    mov edx,eax
    shl eax,16
    or ax,bx       ;eax是8字节段描述符的低4字节，高16位是段基地址的0-15位，低16位是界限符的0-15位

    ;配置段描述符的高4字节，存放在edx寄存器中
    and edx,0xffff0000
    rol edx,8   ;段基地址的24-31位在0-7,16-23在24-31位
    bswap edx   ;交换高和低地址数据24-31位在24-31位，16-23位在0-7位

    xor bx,bx   ;ebx 段界限，16-19位
    or edx,ebx

    or edx,ecx  ;属性，8-11，type;12-15 p dpl s;20-23,p d/b avl l
    ret





gdt_size: dw 0
gdt_base: dd 0x00007e00

times 510-($-$$) db 0
db 0x55,0xaa