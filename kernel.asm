
flat_core_code_seg_sel equ 0x0008
flat_core_data_seg_sel equ 0x0010
flat_user_code_seg_sel equ 0x001b
flat_user_data_seg_sel equ 0x0023

idt_liner_address   equ 0x8001f000 ;中断描述符表基址
core_lin_alloc_at   equ 0x80100000  ;1M后,内核空间动态内存分配起始地址
core_lin_tcb_addr   equ 0x8001f800  ;内核任务tcb 虚拟地址

SECTION header vstart=0x80040000

core_length dd core_end  ;0x00

core_entry  dd start        ;段内偏移,0x04

[bits 32]
SECTION sys_routine vfollows=header
put_string:         ;输入ds:ebx 字符串
    push ecx
    push ebx
    pushfd
    cli
.getc:
    mov cl,[ebx]
    or cl,cl
    jz .exit
    call put_char ;cl 不为0
    inc ebx
    jmp .getc
.exit:
    popfd
    pop ebx
    pop ecx
    ret

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
    and ebx,0x0000ffff

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
    shl bx,1
    mov [0x800b8000+ebx],cl

    shr bx,1
    inc bx

.roll_screen:
    cmp bx,2000
    jl .set_cursor

    push ebx
    cld
    mov esi,0xa0+0x800b8000
    mov edi,0x00+0x800b8000
    mov ecx,1920
    rep movsw
    mov ebx,3840
    mov ecx,80
.cls:
    mov word[ebx+0x800b8000],0x0720
    add bx,2
    loop .cls

    pop ebx
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
    ret
;----------------------------------------------------------------
allocate_a_4k_page:    ;分配一个从空闲物理内存中分配一个4k页，输出eax 物理页地址
    push ebx
    push ecx
    push edx


    xor eax,eax
.b1:
    bts [page_bit_map],eax      ;test and swap bit,page为bit流的起始地址，eax为bit的位置，当前bit置位，把原来的值给cf
    jnc .b2                     ;如果上一条命令，bit的原来的值是0，对应的页空闲，cf被置零，nc跳转
    inc eax
    cmp eax,page_map_len*8
    jl .b1

    mov ebx,message_3
    call put_string
    hlt                         ;没有可分配的页
.b2:
    shl eax,12

    pop edx
    pop ecx
    pop ebx

    ret

;----------------------------------------------------------------
alloc_inst_a_page:      ;为虚拟内存页分配一个物理页，建立映射关系；输入ebx虚拟页地址
    push eax
    push ebx
    push ecx
    push esi

    ;检查虚拟地址是否已经安装页表
    mov esi,ebx
    and esi,0xffc00000  ;高10位页目录内索引
    shr esi,20          ;页目录内索引乘4是这项在页目录这页内的偏移
    or esi,0xffffff000  ;高20位为1，低12位为页内偏移，页目录最高项内的页地址就是此页目录地址，把页目录当页表，在当页访问

    test dword [esi],0x00000001 ;P位，页表是否存在
    jnz .b1             ;存在

    ;创建并安装页表
    call allocate_a_4k_page ;分配一页做页表
    or eax,0x00000007   ;111 user RW P
    mov [esi],eax

    ;清空当前页表
    mov eax,ebx
    and eax,0xffc00000  ;保存高10位
    shr eax,10          ;高10位右移10位，当做页表内索引，把也目录项当页表
    or eax,0xffc00000   ;高10位置一，也目录项是页表，页表作页访问
    mov ecx,1024        ;页表内有
.cls0:
    mov dword [eax],0x00000000
    add eax,4
    loop .cls0

.b1:
    ;检查虚拟内存对应的页表内的物理页是否存在
    mov esi,ebx
    and esi,0xfffff000
    shr esi,10       ;页目录当页表，页表当页,页表索引*4，是页表,页内内偏移
    or esi,0xffc00000   ;高10位置位，页表就是页目录项

    test dword [esi],0x00000001
    jnz .b2           ;存在页

    ;创建并安装页
    call allocate_a_4k_page
    or eax,0x00000007
    mov [esi],eax

.b2:
    pop esi
    pop ecx
    pop ebx
    pop eax
    ret
;---------------------------------------------------------------
create_copy_cur_pdir:       ;创建新页目录，并复制内核的页目录，输出页目录的物理地址
    push esi
    push edi
    push ebx
    push ecx

    call allocate_a_4k_page
    mov ebx,eax
    or ebx,0x00000007
    mov [0xfffffff8],ebx    ;把当前页目录当页表，当页，倒数第二项在页内的偏移，新分配的页登记在页目录的倒数第2项

    invlpg [0xfffffff8]     ;刷新tlb一项。

    mov esi,0xfffff000      ;当前页目录的虚拟页地址
    mov edi,0xffffe000      ;新分配的页目录的虚拟页地址
    mov ecx,1024
    cld
    repe movsd

    pop ecx
    pop ebx
    pop edi
    pop esi
    ret
;----------------------------------------------------------------
task_allock_memory:     ;在指定任务的虚拟内存空间中分配内存；输入ebx，指定task的tcb，ecx希望分配的字节数；输出ecx分配内存的线性地址
    push eax
    push ebx

    mov ebx,[ebx+6]
    mov eax,ebx
    add ecx,ebx         ;本次分配
    push ecx

    ;为内存分配页
    and ebx,0xfffff000
    and ecx,0xfffff000
.next:
    call alloc_inst_a_page

    add ebx,0x1000
    cmp ebx,ecx
    jle .next

    ;将用于下一次分配的线性地址强制按4字节对齐
    pop ecx

    test ecx,0x00000003
    jz .algn
    add ecx,4
    and ecx,0xfffffffc

.algn:
    pop ebx
    mov [ebx+6],ecx  ;保存空闲虚拟内存的起始地址到tcb
    mov ecx,eax

    pop eax
    ret

;---------------------------------------------------------------
allocate_memory: ;从当前任务的虚拟地址空间中分配内存；输入ecx希望分配的字节数；输出ecx 起始线性地址
    push eax
    push ebx

    ; 得到tcb链表首地址
    mov eax,[tcb_chain]

    ;搜索状态为busy的task，
.s0:
    cmp word [eax+0x04],0xffff
    jz .s1
    mov eax,[eax]
    jmp .s0

    ;开始分配内存
.s1
    mov ebx,eax
    call task_allock_memory

    pop ebx
    pop eax

    ret

set_up_gdt_descriptor: ;输入edx:eax 描述符，返回cx 描述符选择子

    push eax
    push ebx
    push edx

    sgdt [pgdt]

    movzx ebx,word [pgdt] ;gdt 界限
    inc ebx
    add ebx,[pgdt+2]

    mov [ebx],eax
    mov [ebx+4],edx

    add word [pgdt],8

    lgdt [pgdt]

    mov ax,[pgdt]
    xor dx,dx
    mov bx,8
    div bx
    mov cx,ax
    shl cx,3   ;界限-7是最后一个描述符的起始偏移地址，也就是选择子

    pop edx
    pop ebx
    pop eax
    ret


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
    ret

make_gate_descriptor:   ;输入eax函数偏移地址，bx选择子，cx属性;输出edx:eax
    push ecx
    push ebx

    push eax
    and eax,0x0000ffff
    shl ebx,16
    or eax,ebx

    pop edx
    and edx,0xffff0000
    or dx,cx

    pop ebx
    pop ecx
    ret
resume_task_execute:    ;恢复指定任务的执行；输入edi新任务的tcb
    mov eax,[edi+10]
    mov [tss+4],eax     ;设置tss的esp0域

    mov eax,[edi+22]
    mov cr3,eax

    mov ds,[edi+34]
    mov es,[edi+36]
    mov fs,[edi+38]
    mov gs,[edi+40]


    test word [edi+32],3    ;ss.RPL=3?只有两种特权级别11和00,从不曾运行的用户任务初始ss是3特权级。之后都是在中断响应中切换，ss0特权
    jnz .to_r3
    mov esp,[edi+70]
    mov ss,[edi+32]
    jmp .do_sw

.to_r3:
    mov eax,[edi+42]
    mov ebx,[edi+46]
    mov ecx,[edi+50]
    mov edx,[edi+54]
    mov esi,[edi+58]
    mov ebp,[edi+66]
    push dword [edi+32]     ;ss
    push dword [edi+70]     ;esp    ;从特权0返回特权3，转换ss和esp
.do_sw:
    push dword [edi+74]     ;eflags
    push dword [edi+30]     ;cs
    push dword [edi+26]     ;eip
    
    not word [edi+0x04]     ;busy
    mov edi,[edi+62]
    iretd

;------------------------------------------
initiate_task_switch:       ;任务切换，输入，输出无
    pushad

    mov eax,[tcb_chain]  ;tcb链表

    cmp eax,0
    jz .return

    ;找到状态位忙的任务（当前任务）
.b0:
    cmp word [eax+0x04],0xffff
    cmove esi,eax      ;相等则mov
    jz .b1
    mov eax,[eax]   ;状态不为busy，下一个tcb
    jmp .b0

.b1:
    mov ebx,[eax]   ;下一个tcb
    or ebx,ebx      ;最后一个tcb的next是0
    jz .b2
    cmp word [ebx+0x04],0x0000
    cmove edi,ebx   ;相等则转移，找到就绪节点，保存到edi
    jz .b3
    mov eax,ebx
    jmp .b1

.b2 :
    mov ebx,[es:tcb_chain]
.b20:
    cmp word [ebx+0x04],0x0000
    cmove edi,ebx
    jz .b3
    mov ebx,[ebx]
    or ebx,ebx
    jz .return  ;到最后一个节点，找不到就绪，结束
    jmp .b20        

    ;esi是当前忙任务，eid是就绪任务
.b3:
    ;保存旧任务的状态
    mov eax,cr3
    mov [esi+22],eax        ;保存cr3
    ; mov [esi+50],ecx  ;开头的pushad保存了eax,ebx,ecx,edx,esp,ebp,esi,edi.所以状态被压栈保存了
    ; mov [esi+54],edx
    ; mov [esi+66],ebp
    mov [esi+70],esp    ;需要esp pop
    mov dword [esi+26],.return
    mov [esi+30],cs
    mov [esi+32],ss
    mov [esi+34],ds
    mov [esi+36],es
    mov [esi+38],fs
    mov [esi+40],gs
    pushfd
    pop dword [esi+74]

    not word [esi+0x04]     ;当前任务tcb esi。设置任务状态为就绪

    jmp resume_task_execute

.return:
    popad

    ret

;-----------------------------------------------
terminate_current_task:  ;终结当前任务，把任务tcb中的状态设置为0x3333,然后跳转到其他任务

    mov eax,[tcb_chain]

    ;搜索状态位忙的tcb(当前任务)
.s0:
    cmp word [eax+0x04],0xffff
    jz .s1
    mov eax,[eax]
    jmp .s0

.s1
    mov word [eax+0x04],0x3333

    ;遍历，找到就绪任务
    mov ebx,[tcb_chain]

.s2:
    cmp word [ebx+0x04],0x0000
    jz .s3
    mov ebx,[ebx]
    jmp .s2


.s3:
    not word [ebx+0x04]
    jmp far [ebx+0x14]

;---------------------------------------------------
general_interrupt_handler:      ;通用中断处理
    push eax
    push ebx

    mov al,0x20
    out 0xa0,al        ;发送给主片中断完成命令
    out 0x20,al        ;发送给从片中断完成
    pop ebx
    pop eax
    
    iretd

;-----------------------------------------------------
general_exception_handler:  ;通用异常处理过程
    mov ebx,excep_msg
    call put_string
    ; hlt
    iretd

;--------------------------------------------------
rtm_0x70_interrupt_handle:  ;实时时钟中断处理过程
    pushad

    mov al,0x20
    out 0xa0,al     ;发送给8259A主片中断完成命令
    out 0x20,al     ;发送给8259A从片

    mov al,0x0c     ;rtc 寄存器C，开放NMI
    out 0x70,al
    in al,0x71      ;读出RTC中断类型，清空内容，为了下一次中断能够触发。只设置了更新完成中断，所以不判断类型

    mov ebx,rtc_interrupt_msg
    call put_string

    ; 请求任务调度
    call initiate_task_switch

    popad
    iretd

int_0x88_handler:
    call [eax*4 + sys_call]
    iretd
;--------------------------------------------------
do_task_clean:  ;没有内存管理，无法回收资源，不做任何处理
    ret

SECTION core_data vfollows=sys_routine

pgdt        dw 0
            dd 0
pidt        dw 0
            dd 0

page_bit_map    db  0xff,0xff,0xff,0xff,0xff,0xff,0x55,0x55    ;2M内存的位图
                db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                db  0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
                db  0x55,0x55,0x55,0x55,0x55,0x55,0x55,0x55
                db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
                db  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
page_map_len    equ $-page_bit_map
sys_call        dd put_string
                dd read_hard_disk_0
                dd terminate_current_task
                dd initiate_task_switch
                dd allocate_memory

ram_alloc  dd 0x00100000   ;用户内存起始地址，初始化为1M，向上分配

message_1  db  '  If you seen this message,that means we '
           db  'are now in protect mode,and the system '
           db  'core is loaded,and the video display '
           db  'routine works perfectly.',0x0d,0x0a,0
message_2  db  'Tss is loader',0x0d,0x0a,0
message_3  db  '**************No more pages************',0x0d,0x0a,0
message_5  db  ' Loading user program...',0

do_status        db  'Done.',0x0d,0x0a,0

message_6  db  0x0d,0x0a,0x0a,0x0a,0x0a
            db 'User program terminated,control returned.',0
excep_msg   db '********Exception encounted********'
            db 0x0d,0x0a,0

general_interrupt_msg db "********generatal interrupt********" ,0x0d,0x0a,0

rtc_interrupt_msg db "interrupt after rtc update",0x0d,0x0a,0

core_buf times 2048 db 0
tss      times 128 db 0

esp_pointer db 0

cpu_brnd0  db 0x0d,0x0a,' cpu id ',0
cpu_brand times 52 db 0
cpu_brnd1  db 0x0d,0x0a,0x0d,0x0a,0

tcb_chain      dd 0

core_msg1      db 0x0d,0x0a
                db '[CORE TASK]: I am running at CPL=0.Now,create '
                db 'user task and switch to it.',0x0d,0x0a,0

core_msg2       db 0x0d,0x0a
                db '[CORE TASK]: I am working!',0x0d,0x0a,0

core_msg3       db 0x0d,0x0a
                db '[CORE TASK]: No task to be switched,sleep!'
                db 0x0d,0x0a,0

SECTION core_code vfollows=core_data

load_relocate_program:      ;push 起始逻辑扇区号，push tcb 
    pushad

    mov ebp,esp

    ;清空当前页目录的前半部分，就是低2G的内存空间，用户虚拟空间
    mov ebx,0xfffff000
    xor esi,esi
.clsp:
    mov dword [ebx+esi*4],0x00000000
    inc esi
    cmp esi,2
    jl .clsp

    mov ebx,cr3
    mov cr3,ebx     ;刷新tlb

    mov eax,[ebp+10*4]  ;取出push的扇区号
    mov ebx,core_buf
    call read_hard_disk_0

    ;判断程序大小
    mov eax,[core_buf]
    mov ebx,eax
    and ebx,0xfffffe00
    add ebx,512       ;eax/512*512+512
    test eax,0x000001ff
    cmovnz eax,ebx     ;eax最后9位，不全为零，不是512的整数倍，向上取整数倍

    mov esi,[ebp+9*4]  ;取出push的 tcb 地址，near call ,eip 4个字节，pushad 8*4个字节
    mov ecx,eax
    mov ebx,esi
    call task_allock_memory

    mov ebx,ecx
    xor edx,edx
    mov ecx,512
    div ecx
    mov ecx,eax

    mov eax,[ebp+10*4]
.b1:
    call read_hard_disk_0
    inc eax
    loop .b1

    ;用户堆栈
    mov ebx,esi
    mov ecx,4096
    call task_allock_memory
    mov ecx, [esi+6]    ;空闲虚拟内存基址，就是刚分配的内存的上界
    mov dword [esi+70],ecx  ;esp

    ;特权堆栈
    mov ebx,esi
    mov ecx,4096
    call task_allock_memory
    mov ecx, [esi+6]    ;空闲虚拟内存基址，就是刚分配的内存的上界
    mov dword [esi+10],ecx  ;esp

    ;创建用户任务的页目录
    call create_copy_cur_pdir
    mov [esi+22],eax

    mov word [esi+30],flat_user_code_seg_sel    ;tcb cs
    mov word [esi+32],flat_user_data_seg_sel    ;tcb ss
    mov word [esi+34],flat_user_data_seg_sel    ;tcb ds
    mov word [esi+36],flat_user_data_seg_sel    ;tcb es
    mov word [esi+38],flat_user_data_seg_sel    ;tcb fs
    mov word [esi+40],flat_user_data_seg_sel    ;tcb gs

    mov eax, [0x04]     ;用户页映射安装在当前内核任务页目录的低端,所以可以直接读用户数据
    mov [esi+26],eax    ;保存到eip域
    pushfd
    pop dword [esi+74]  ;tcb eflags
    mov word [esi+4],0 ;tcb 就绪

    popad
    ret 8
;----------------------------------------------------------------------
append_to_tcb_link:     ;在TCB链上追加任务控制块;输入ecx是tcb的线性基地址
    push eax
    push edx
    pushfd
    cli

    mov dword [ecx+0],0;下一个任务指针

    mov eax,[tcb_chain]     ;TCB表头指针
    or eax,eax
    jz .notcb
.searc:
    mov edx,eax
    mov eax,[edx+0x00] ;下一个tcb指针
    or eax,eax           
    jnz .searc

    mov [edx+0x00],ecx   ;加到链表中
    jmp .retpc

.notcb
    mov [tcb_chain],ecx

.retpc
    popfd
    pop edx
    pop eax

    ret
;----------------------------------------------------------------------------
start:
    ;创建中断描述符表idt
    ;前20个是处理器异常使用的
    mov eax,general_exception_handler
    mov bx,flat_core_code_seg_sel
    mov cx,0x8e00           ;中断门，P=1 00 特权 s=0系统段 type 1110 32位中断门
    call make_gate_descriptor

    mov ebx,idt_liner_address
    xor esi,esi
.idt0:
    mov [ebx+esi*8],eax
    mov [ebx+esi*8+4],edx
    inc esi
    cmp esi,19
    jle .idt0           ;安装0-19 异常处理过程


    ;安装其余的中断门
    mov eax,general_interrupt_handler
    mov bx,flat_core_code_seg_sel
    mov cx,0x8e00           ;中断门
    call make_gate_descriptor

    mov ebx,idt_liner_address
.idt1:
    mov [ebx+esi*8],eax
    mov [ebx+esi*8+4],edx
    inc esi
    cmp esi,255         ;安装全部256个中断门
    jle .idt1

;设置实时时钟中断处理
    mov eax,rtm_0x70_interrupt_handle
    mov bx,flat_core_code_seg_sel
    mov cx,0x8e00
    call make_gate_descriptor

    mov ebx,idt_liner_address
    mov [ebx+0x70*8],eax     ;rtc中断号是0x70
    mov [ebx+0x70*8+4],edx

    ;设置系统调用的中断处理过程
    mov eax,int_0x88_handler
    mov bx,flat_core_code_seg_sel
    mov cx,0xee00            ;3特权级
    call make_gate_descriptor

    mov ebx,idt_liner_address
    mov [ebx+0x88*8],eax
    mov [ebx+0x88*8+4],edx

    mov word [pidt],256*8-1 ;中断描述符表的界限
    mov dword [pidt+2],idt_liner_address
    lidt [pidt]

    ;测试系统调用
    mov ebx,do_status
    mov eax,0
    int 0x88

    ;设置8259A中断控制器,0x20,0x21是主片的端口
    mov al,0x11     ;icw1 中断控制字1，控制命令1，设置触发方式 边沿触发?,书上说是电平触发和是级联的形式
    out 0x20,al
    mov al,0x20
    out 0x21,al     ;icw2,0x20说明，硬件向量号偏移32，0->32 1->31
    mov al,0x04
    out 0x21,al     ;icw3 0x04,发给主片时，位n置位说明n位连接从片
    mov al,0x01
    out 0x21,al      ;icw4 0x01,非自动结束方式，需要向中断控制器写入eoi命令，才能继续下次触发

    ;从片端口是0xa0，0xa1
    mov al,0x11
    out 0xa0,al
    mov al,0x70
    out 0xa1,al     ;icw2,起始中断向量0x70
    mov al,0x02
    out 0xa1,al     ;icw3,发送给从片时，低3位的值，说明级联主片的引脚位置，2引脚连接主片
    mov al,0x01
    out 0xa1,al

    ;设置rtc
    mov al,0x0b
    or al,0x80      ;阻断NMI
    out 0x70,al     
    mov al,0x12
    out 0x71,al     ;设置B寄存器，禁止周期性中断，开放更新结束后中断，bcd码，24小时制

    in al,0xa1      ;中断控制器从片 IMR 中断屏蔽寄存器
    and al,0xfe     ;清除位0，此pin连接rtc
    out 0xa1,al

    mov al,0x0c
    out 0x70,al
    in al,0x71      ;读寄存器C，复位未决的中断状态
    sti             ;EFLAGS 开放可屏蔽中断

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
    call put_string
    mov ebx,cpu_brand
    call put_string
    mov ebx,cpu_brnd1
    call put_string


    ;创建任务状态段tss。整个系统只需要一个tss，使用tcb保存上下文
    mov ecx,32
    xor ebx,ebx
.clear:
    mov dword [tss+ebx],0
    add ebx,4
    loop .clear

    ;只使用了0特权级和3特权级。所以，只会发生3和0之间的切换。tss中只需要ss0
    mov word [tss+8],flat_core_data_seg_sel
    mov word [tss+102],103  ;没有I/O许可位图

    ;创建tss描述符，安装到gdt
    mov eax,tss
    mov ebx,103
    mov ecx,0x00008900      ;0特权级，tss描述符
    call make_seg_descriptor
    call set_up_gdt_descriptor

    ltr cx

    mov ebx,message_2
    call put_string

    ;为内核任务创建任务控制块tcb
    mov ecx,core_lin_tcb_addr
    mov word [es:ecx+0x04],0xffff   ;设置内核任务状态为busy，内核任务是current task
    mov dword [es:ecx+6],core_lin_alloc_at   ;登记内核任务空闲虚拟空间起始地址,和c19不一样，c19,06用于存放app首地址，0x46存放空闲虚拟地址开始
    call append_to_tcb_link

    ;现在可以认为“程序管理器中任务正在进行”
    mov ebx,core_msg1
    call put_string

    ;创建用户任务控制块tcb
    mov ecx,128
    call allocate_memory    ;从当前任务（内核任务）的虚拟地址空间中分配内存，返回的虚拟地址是在高端的
    mov word [ecx+0x04],0    ;就绪任务
    mov dword [ecx+6],0   ;用户任务的虚拟地址空间在低端，所以从空闲内存从0起始
    push dword 50
    push ecx
    call load_relocate_program
    call append_to_tcb_link

    ;可以创建更多的任务
    mov ecx,128
    call allocate_memory
    mov word [es:ecx+0x04],0    ;就绪任务
    mov dword [es:ecx+6],0

    push dword 100
    push ecx

    call load_relocate_program
    call append_to_tcb_link

.do_switch:
    mov ebx,core_msg2
    call put_string
    nop
    nop
    nop

    hlt
    jmp .do_switch


SECTION core_trail
core_end: