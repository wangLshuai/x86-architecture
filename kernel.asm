
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
    retf

allocate_memory: ;分配内存，输入ecx分配的字节，输出ecx 起始线性地址
    push ds
    push eax
    push ebx

    mov eax,core_data_seg_sel
    mov ds,eax

    mov eax,[ram_alloc]
    add eax,ecx

    mov ecx,[ram_alloc]

    ;4字节对齐下一次分配的起始地址
    mov ebx,eax
    add ebx,0xfffffffc
    add ebx,4
    test eax,0x00000003
    cmovnz eax,ebx
    mov [ram_alloc],eax

    pop ebx
    pop eax
    pop ds

    retf

set_up_gdt_descriptor: ;输入edx:eax 描述符，返回cx 描述符选择子

    push eax
    push ebx
    push edx

    push ds
    push es

    mov ebx,core_data_seg_sel
    mov ds,bx
    sgdt [pgdt]

    mov ebx,mem_0_4_gb_seg_sel
    mov es,ebx

    movzx ebx,word [pgdt] ;gdt 界限
    inc ebx
    add ebx,[pgdt+2]

    mov [es:ebx],eax
    mov [es:ebx+4],edx

    add word [pgdt],8

    lgdt [pgdt]

    mov ax,[pgdt]
    xor dx,dx
    mov bx,8
    div bx
    mov cx,ax
    shl cx,3   ;界限-7是最后一个描述符的起始偏移地址，也就是选择子

    pop es
    pop ds
    pop edx
    pop ebx
    pop eax
    retf


make_seg_descriptor:       ;输入EAX 线性地址，段的基地址，EBX 界限，ECX属性，返回EDX:EAX 段描述符
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
    retf


SECTION core_data vstart=0

pgdt        dw 0
            dd 0
ram_alloc  dd 0x00100000   ;用户内存起始地址，初始化为1M，向上分配

;符号地址检索表
salt:
    salt_1      db '@PrintString'
                times 256-($-salt_1) db 0
                dd put_string
                dw sys_routine_seg_sel

    salt_2      db '@ReadDiskData'
                times 256-($-salt_2) db 0
                dd read_hard_disk_0
                dw sys_routine_seg_sel
    salt_3      db '@PrintDwordAsHexString'
                times 256-($-salt_3) db 0
                dd 0
                dw 0
    
    salt_4      db '@TerminateProgram'
                times 256-($-salt_4) db 0
                dd return_point
                dw core_code_seg_sel
    salt_item_len equ $-salt_4
    salt_items  equ ($-salt)/salt_item_len

message_1  db  '  If you seen this message,that means we '
           db  'are now in protect mode,and the system '
           db  'core is loaded,and the video display '
           db  'routine works perfectly.',0x0d,0x0a,0
message_5  db  ' Loading user program...',0

do_status        db  'Done.',0x0d,0x0a,0

message_6  db  0x0d,0x0a,0x0a,0x0a,0x0a
            db 'User program terminated,control returned.',0

core_buf times 2048 db 0

esp_pointer db 0

cpu_brnd0  db 0x0d,0x0a,' cpu id ',0
cpu_brand times 52 db 0
cpu_brnd1  db 0x0d,0x0a,0x0d,0x0a,0

SECTION core_code vstart=0

load_relocate_program:      ;输入esi 起始逻辑扇区号，输出ax 段选择子
    push ebx
    push ecx
    push edx
    push esi
    push edi

    push ds
    push es

    mov eax,core_data_seg_sel
    mov ds,eax

    mov eax,esi
    mov ebx,core_buf
    call sys_routine_seg_sel:read_hard_disk_0

    ;判断程序大小
    mov eax,[core_buf]
    mov ebx,eax
    and ebx,0xfffffe00
    add ebx,512       ;eax/512*512+512
    test eax,0x000001ff
    cmovnz eax,ebx     ;eax最后9位，不全为零，不是512的整数倍，向上取整数倍

    mov ecx,eax
    call sys_routine_seg_sel:allocate_memory
    mov ebx,ecx
    push ebx
    xor edx,edx
    mov ecx,512
    div ecx
    mov ecx,eax

    mov eax,mem_0_4_gb_seg_sel
    mov ds,eax

    mov eax,esi
.b1:
    call sys_routine_seg_sel:read_hard_disk_0
    inc eax
    loop .b1

    pop edi             ;首地址 push ebx
    mov eax,edi
    mov ebx,[edi+0x04]  ;app head len
    dec ebx             ;界限
    mov ecx,0x00409200  ;1字节粒度，32位尺度，p存在，00特权，数据或代码段，读写数据段，向上扩展
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [edi+0x04],cx

    ;程序代码段描述符
    mov eax,edi
    add eax,[edi+0x14]  ;代码段汇编地址加上 二进制加载首地址
    mov ebx,[edi+0x18]
    dec ebx
    mov ecx,0x00409800 ;只执行代码段
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [edi+0x14],cx


    ;程序数据段;
    mov eax,edi
    add eax,[edi+0x1c]
    mov ebx,[edi+0x20]
    dec ebx
    mov ecx,0x00409200
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [edi+0x1c],cx

    ;程序堆栈段
    mov ecx,[edi+0x0c]
    mov ebx,0x00100000
    sub ebx,ecx
    mov eax,4096
    mul dword [edi+0x0c]
    mov ecx,eax
    call sys_routine_seg_sel:allocate_memory
    add eax,ecx ;向下扩展的粒度为4kb的段,有n个4k大小，基址+(2^20-x)*4k 为下限ecx,或者基址+2^32 = ecx + n*4k，所以基址=ecx+n*4k
    mov ecx,0x00c09600
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [edi+0x08],cx

    ;重定位salt
    mov eax,[edi+0x04]
    mov es,eax      ;用户头段
    mov eax,core_data_seg_sel
    mov ds,eax      

    cld

    mov ecx,[es:0x24]   ;salt 数目
    mov edi,0x28        ;salt 起始偏移

.b2:
    push ecx
    push edi

    mov ecx,salt_items
    mov esi,salt

.b3:            ;循环比较core_data中的所有salt item
    push edi
    push esi
    push ecx

    mov ecx,64   ;最多比较64次
    repe cmpsd  ;ds:esi es:edi 每次比较双字，相等则继续比较下一个双字
    jnz .b4
    mov eax,[esi] ;匹配,取出core_data salt_item后的段内偏移地址
    mov [es:edi-256],eax
    mov ax,[esi+4] ;选择子
    mov [es:edi-252],ax

.b4:

    pop ecx
    pop esi
    add esi,salt_item_len
    pop edi
    loop .b3
    ;遍历core_data中的所有salt item循环 结束

    pop edi
    add edi,256
    pop ecx
    loop .b2  ;app 中的下一个item


    mov ax,[es:0x04]    ;保存app head 段选择子

    pop es
    pop ds

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

start:
    pushad

    mov ax,core_data_seg_sel
    mov ds,ax

    mov ebx,message_1
    call sys_routine_seg_sel:put_string

    ;显示处理器品牌信息
    mov eax,0x80000002
    cpuid
    mov [cpu_brand + 0x00],eax
    mov [cpu_brand + 0x04],ebx
    mov [cpu_brand + 0x08],ecx
    mov [cpu_brand + 0x0c],edx

    mov eax,0x80000003
    cpuid
    mov [cpu_brand + 0x10],eax
    mov [cpu_brand + 0x14],ebx
    mov [cpu_brand + 0x18],ecx
    mov [cpu_brand + 0x1c],edx

    mov eax,0x80000004
    mov [cpu_brand + 0x20],eax
    mov [cpu_brand + 0x24],ebx
    mov [cpu_brand + 0x28],ecx
    mov [cpu_brand + 0x2c],edx

    mov ebx,cpu_brnd0
    call sys_routine_seg_sel:put_string
    mov ebx,cpu_brand
    call sys_routine_seg_sel:put_string
    mov ebx,cpu_brnd1
    call sys_routine_seg_sel:put_string

    mov ebx,message_5
    call sys_routine_seg_sel:put_string

    mov esi,50
    call load_relocate_program

    mov ebx,do_status
    call sys_routine_seg_sel:put_string

    mov [esp_pointer],esp

    mov ds,ax
    jmp far [0x10]

    popad
    retf

return_point:
    mov eax,core_data_seg_sel
    mov ds,eax

    mov eax,core_stack_seg_sel
    mov ss,eax
    mov esp,[esp_pointer]

    mov ebx,message_6
    call sys_routine_seg_sel:put_string

    hlt

SECTION core_trail
core_end: