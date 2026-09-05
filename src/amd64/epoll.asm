; epoll helpers: create epoll fd, add FDs with EPOLLIN, wait for one event

global epoll_create_fd
global epoll_add_fd
global epoll_wait_once

%include "macros.inc"
%include "syscalls_amd64.inc"
extern g_verbose
extern log_prefix_num
extern get_timestamp_ptr
extern get_timestamp_ptr

section .bss
align 8
epoll_events_buf:   resb EPOLL_EVENT_SIZE * 4

section .text

; rax = epoll_create1(0)
epoll_create_fd:
    mov rdi, EPOLL_CLOEXEC
    SYSCALL SYS_epoll_create1
    test rax, rax
    js .ret
    ; log fd number
    push rax
    mov rdx, rax
    lea rdi, [rel log_epfd_created_prefix]
    mov rsi, log_epfd_created_prefix_len
    call log_prefix_num
    pop rax
.ret:
    ret

; epoll_add_fd(epfd, fd)
; rdi=epfd, rsi=fd
epoll_add_fd:
    ; x86-64 kernel epoll_event is EPOLL_PACKED: events @0, data @4, size 12.
    ; Keep a 16-byte scratch slot but place data at offset 4.
    sub rsp, EPOLL_EVENT_SIZE
    mov dword [rsp], EPOLLIN       ; events
    mov qword [rsp+4], rsi         ; data = fd (EPOLL_PACKED: data at offset 4)
    mov rdx, rsi                   ; arg3: fd
    mov rsi, EPOLL_CTL_ADD         ; arg2: op
    mov r10, rsp                   ; arg4: event pointer
    ; SYSCALL: epoll_ctl(epfd, op, fd, event)
  .ctl_retry:
    mov rax, SYS_epoll_ctl
    syscall
    test rax, rax
    jns .ctl_ok
    mov rbx, rax
    neg rbx
    cmp rbx, EINTR
    je .ctl_retry
    LOG log_epoll_ctl_err, log_epoll_ctl_err_len
    mov rax, -1
    jmp .ctl_out
.ctl_ok:
    ; log added fd number (from rdx)
    mov rdx, rdx
    lea rdi, [rel log_epoll_add_prefix]
    mov rsi, log_epoll_add_prefix_len
    call log_prefix_num
    xor rax, rax
.ctl_out:
    add rsp, EPOLL_EVENT_SIZE
    ret

; epoll_wait_once(epfd) -> rax = ready_fd (from event.data) or <0 on error
epoll_wait_once:
    ; prepare buffer
    lea rsi, [rel epoll_events_buf]
    mov rdx, 4             ; maxevents
    mov r10, -1            ; timeout = -1 (block)
    xor r8, r8             ; sigmask = NULL
    xor r9, r9             ; sigsetsize = 0
  .wait_retry:
    mov rax, SYS_epoll_pwait
    syscall
    test rax, rax
    jns .count_ok
    mov rbx, rax
    neg rbx
    cmp rbx, EINTR
    je .wait_retry
    LOG log_epoll_wait_err, log_epoll_wait_err_len
    jmp .err
  .count_ok:
    ; rax = number of events
    cmp rax, 1
    jl .err
    ; read data of first event
    lea rbx, [rel epoll_events_buf]
    mov rax, [rbx+4]       ; data (u64) at offset 4 (EPOLL_PACKED)
    ret
.err:
    mov rax, -1
    ret

section .rodata
log_epfd_created_prefix:     db "DEBUG: epoll fd created fd=", 0
log_epfd_created_prefix_len: equ $ - log_epfd_created_prefix - 1
log_epoll_add_prefix:        db "DEBUG: added FD to epoll fd=", 0
log_epoll_add_prefix_len:    equ $ - log_epoll_add_prefix - 1
log_epoll_ctl_err:    db "ERROR: epoll_ctl failed", 10
log_epoll_ctl_err_len: equ $ - log_epoll_ctl_err
log_epoll_wait_err:   db "ERROR: epoll_pwait failed", 10
log_epoll_wait_err_len: equ $ - log_epoll_wait_err
