.include "syscalls_aarch64.inc"
.include "macros_arm64.inc"

.text
.align 2
.global _start
.global g_verbose
.global g_exit_code_base
.global g_arm64_fallback

.extern do_spawn
.extern forward_signal_to_group
.extern reap_children_nonblock
.extern extract_exit_code
.extern setup_signals_and_fd
.extern read_signalfd_once
.extern get_wait_status_ptr
.extern get_signalfd_fd
.extern epoll_create_fd
.extern epoll_add_fd
.extern epoll_wait_once
.extern create_grace_timerfd
.extern read_timerfd_tick
.extern log_prefix_num
.extern get_timestamp_ptr
.extern parse_u64_dec
.extern parse_u64_dec_checked
.extern set_sig_bit

.section .rodata
.align 3
usage_msg:         .asciz "usage: mini-init-arm64 [--verbose|-v] [--version|-V] -- <cmd> [args...]\n"
.equ usage_msg_len, . - usage_msg - 1
.include "version_arm64.inc"
log_first_soft:    .asciz "DEBUG: first soft signal received"
.equ log_first_soft_len, . - log_first_soft - 1
log_escalate_kill: .asciz "DEBUG: escalating to SIGKILL"
.equ log_escalate_kill_len, . - log_escalate_kill - 1
log_escalate_skip_dead_pgid: .asciz "DEBUG: grace timer fired but PGID is gone; skipping SIGKILL"
.equ log_escalate_skip_dead_pgid_len, . - log_escalate_skip_dead_pgid - 1
log_sigchld_ok:    .asciz "DEBUG: SIGCHLD handled"
.equ log_sigchld_ok_len, . - log_sigchld_ok - 1
log_restart:       .asciz "DEBUG: restarting child"
.equ log_restart_len, . - log_restart - 1
log_max_restarts:  .asciz "DEBUG: max restarts reached, exiting"
.equ log_max_restarts_len, . - log_max_restarts - 1
log_backoff_wait:  .asciz "DEBUG: waiting for backoff before restart"
.equ log_backoff_wait_len, . - log_backoff_wait - 1
log_signal_prefix: .asciz "DEBUG: signal="
.equ log_signal_prefix_len, . - log_signal_prefix - 1
log_grace_secs_prefix: .asciz "DEBUG: grace_seconds="
.equ log_grace_secs_prefix_len, . - log_grace_secs_prefix - 1
log_restart_count_prefix: .asciz "DEBUG: restart_count="
.equ log_restart_count_prefix_len, . - log_restart_count_prefix - 1
log_restart_backoff_prefix: .asciz "DEBUG: restart_backoff_seconds="
.equ log_restart_backoff_prefix_len, . - log_restart_backoff_prefix - 1
log_warn_bad_grace: .asciz "WARN: invalid EP_GRACE_SECONDS; using default"
.equ log_warn_bad_grace_len, . - log_warn_bad_grace - 1
log_warn_clamp_grace: .asciz "WARN: EP_GRACE_SECONDS too large; clamping"
.equ log_warn_clamp_grace_len, . - log_warn_clamp_grace - 1
log_warn_bad_exit_base: .asciz "WARN: invalid EP_EXIT_CODE_BASE; using default"
.equ log_warn_bad_exit_base_len, . - log_warn_bad_exit_base - 1
log_warn_range_exit_base: .asciz "WARN: EP_EXIT_CODE_BASE out of range (0..255); using default"
.equ log_warn_range_exit_base_len, . - log_warn_range_exit_base - 1
log_warn_bad_max_restarts: .asciz "WARN: invalid EP_MAX_RESTARTS; using default"
.equ log_warn_bad_max_restarts_len, . - log_warn_bad_max_restarts - 1
log_warn_bad_backoff: .asciz "WARN: invalid EP_RESTART_BACKOFF_SECONDS; using default"
.equ log_warn_bad_backoff_len, . - log_warn_bad_backoff - 1
	log_warn_clamp_backoff: .asciz "WARN: EP_RESTART_BACKOFF_SECONDS too large; clamping"
	.equ log_warn_clamp_backoff_len, . - log_warn_clamp_backoff - 1
	log_warn_grace_timer_unavailable: .asciz "WARN: grace timer unavailable; checking child before escalation"
	.equ log_warn_grace_timer_unavailable_len, . - log_warn_grace_timer_unavailable - 1
	log_warn_backoff_timer_epoll_failed: .asciz "WARN: backoff timer could not be added to epoll; restarting immediately"
	.equ log_warn_backoff_timer_epoll_failed_len, . - log_warn_backoff_timer_epoll_failed - 1
	log_info_child_exited_ignore_signal: .asciz "DEBUG: child already exited; ignoring non-shutdown signal during restart backoff"
	.equ log_info_child_exited_ignore_signal_len, . - log_info_child_exited_ignore_signal - 1
	log_info_child_exited_cancel_restart: .asciz "DEBUG: shutdown requested during restart backoff; exiting without restart"
	.equ log_info_child_exited_cancel_restart_len, . - log_info_child_exited_cancel_restart - 1
log_after_sfd:     .asciz "DEBUG: after setup_signals_and_fd"
.equ log_after_sfd_len, . - log_after_sfd - 1
log_fallback:      .asciz "DEBUG: using ARM64 fallback (wait4-only)"
.equ log_fallback_len, . - log_fallback - 1
log_child_pid:     .asciz "DEBUG: child pid="
.equ log_child_pid_len, . - log_child_pid - 1
log_epoll_add_result: .asciz "DEBUG: epoll_add_fd returned="
.equ log_epoll_add_result_len, . - log_epoll_add_result - 1
log_epoll_add_enter: .asciz "DEBUG: entering epoll_add_fd"
.equ log_epoll_add_enter_len, . - log_epoll_add_enter - 1
log_epoll_add_exit: .asciz "DEBUG: exited epoll_add_fd"
.equ log_epoll_add_exit_len, . - log_epoll_add_exit - 1
delim_str:         .asciz "--"
v1_str:            .asciz "-v"
v2_str:            .asciz "--verbose"
ver1_str:          .asciz "-V"
ver2_str:          .asciz "--version"
ep_pref:           .asciz "EP_GRACE_SECONDS="
ep_subreaper_pref: .asciz "EP_SUBREAPER="
ep_exit_base_pref: .asciz "EP_EXIT_CODE_BASE="
ep_restart_enabled_pref: .asciz "EP_RESTART_ENABLED="
ep_max_restarts_pref: .asciz "EP_MAX_RESTARTS="
ep_restart_backoff_pref: .asciz "EP_RESTART_BACKOFF_SECONDS="
ep_arm64_fallback_pref: .asciz "EP_ARM64_FALLBACK="

.section .bss
.align 3
g_verbose:        .skip 8
g_child_pid:      .skip 8
g_child_exited:   .skip 8
g_child_status:   .skip 8
g_grace_secs:     .skip 8
g_shutdown:       .skip 8
g_killed:         .skip 8
g_epfd:           .skip 8
g_sfd:            .skip 8
g_tfd:            .skip 8
g_argv_exec:      .skip 8
g_envp:           .skip 8
g_exit_code_base: .skip 8
g_restart_enabled: .skip 8
g_max_restarts:   .skip 8
g_restart_count:  .skip 8
g_restart_backoff: .skip 8
g_backoff_tfd:    .skip 8
g_arm64_fallback: .skip 8

.text

// int str_eq(const char *a, const char *b)
str_eq:
    mov x2, x0
    mov x3, x1
.str_loop:
    ldrb w4, [x2]
    ldrb w5, [x3]
    cmp w4, w5
    bne .str_ne
    cbz w4, .str_eq
    add x2, x2, #1
    add x3, x3, #1
    b .str_loop
.str_eq:
    mov x0, #1
    ret
.str_ne:
    mov x0, #0
    ret

// const char* prefix_match("NAME=", env)
prefix_match:
    mov x2, x0  // pattern
    mov x3, x1  // env
.pm_loop:
    ldrb w4, [x2]
    cbz w4, .pm_no
    ldrb w5, [x3]
    cmp w4, w5
    bne .pm_no
    cmp w4, #'='
    beq .pm_value
    add x2, x2, #1
    add x3, x3, #1
    b .pm_loop
.pm_value:
    add x3, x3, #1
    mov x0, x3
    ret
.pm_no:
    mov x0, #0
    ret

_start:
    // Linux AArch64 process entry: argc/argv/envp are on the initial stack
    // [sp] = argc (u64), [sp+8] = argv[0], ..., then NULL, then envp pointers...
    ldr x19, [sp]        // argc
    add x20, sp, #8      // argv**
    lsl x22, x19, #3     // argc * 8
    add x21, x20, x22    // &argv[argc]
    add x21, x21, #8     // envp**

    // defaults
    adrp x0, g_verbose
    add x0, x0, :lo12:g_verbose
    str xzr, [x0]

    // zero rest
    adrp x2, g_child_pid
    add x2, x2, :lo12:g_child_pid
    mov x3, x2
    mov x4, #0
    mov x5, #17  // count for global variables
.zero_globals:
    str x4, [x3]
    add x3, x3, #8
    subs x5, x5, #1
    cbnz x5, .zero_globals

    adrp x0, g_grace_secs
    add x0, x0, :lo12:g_grace_secs
    mov x1, #10
    str x1, [x0]
    adrp x0, g_exit_code_base
    add x0, x0, :lo12:g_exit_code_base
    mov x1, #128
    str x1, [x0]
    adrp x0, g_arm64_fallback
    add x0, x0, :lo12:g_arm64_fallback
    mov x1, #0
    str x1, [x0]
    adrp x0, g_restart_backoff
    add x0, x0, :lo12:g_restart_backoff
    mov x1, #1
    str x1, [x0]

    // parse argv
    mov x22, #1          // i
.parse_argv:
    cmp x22, x19
    bge .argv_done
    lsl x23, x22, #3
    add x24, x20, x23
    ldr x25, [x24]

    // "--"
    adrp x0, delim_str
    add x0, x0, :lo12:delim_str
    mov x1, x25
    bl str_eq
    cmp x0, #1
    beq .found_delim

    // "-v"
    adrp x0, v1_str
    add x0, x0, :lo12:v1_str
    mov x1, x25
    bl str_eq
    cmp x0, #1
    beq .set_verbose

    // "--verbose"
    adrp x0, v2_str
    add x0, x0, :lo12:v2_str
    mov x1, x25
    bl str_eq
    cmp x0, #1
    beq .set_verbose

    // "-V"
    adrp x0, ver1_str
    add x0, x0, :lo12:ver1_str
    mov x1, x25
    bl str_eq
    cmp x0, #1
    beq .show_version

    // "--version"
    adrp x0, ver2_str
    add x0, x0, :lo12:ver2_str
    mov x1, x25
    bl str_eq
    cmp x0, #1
    beq .show_version

    add x22, x22, #1
    b .parse_argv

.show_version:
    mov x0, #1
    adrp x1, version_msg_arm64
    add x1, x1, :lo12:version_msg_arm64
    mov x2, version_msg_arm64_len
    SYSCALL SYS_write
    mov x0, #0
    SYSCALL SYS_exit

.set_verbose:
    adrp x0, g_verbose
    add x0, x0, :lo12:g_verbose
    mov x1, #1
    str x1, [x0]
    add x22, x22, #1
    b .parse_argv

.found_delim:
    add x23, x22, #1
    lsl x23, x23, #3
    add x23, x20, x23
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    str x23, [x0]
    b .argv_done

.argv_done:
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    ldr x1, [x0]
    cbnz x1, .have_cmd

    mov x0, #2
    adrp x1, usage_msg
    add x1, x1, :lo12:usage_msg
    mov x2, #usage_msg_len
    SYSCALL SYS_write
    mov x0, #2
    SYSCALL SYS_exit

.have_cmd:
    // store envp
    adrp x0, g_envp
    add x0, x0, :lo12:g_envp
    str x21, [x0]

    // EP_GRACE_SECONDS
    mov x23, x21
.find_env:
    ldr x24, [x23]
    cbz x24, .env_done
    adrp x0, ep_pref
    add x0, x0, :lo12:ep_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_env
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .bad_grace
    tbnz x0, #63, .clamp_grace
    adrp x2, g_grace_secs
    add x2, x2, :lo12:g_grace_secs
    str x0, [x2]
    b .env_done
.clamp_grace:
    mov x0, #0x7fffffffffffffff
    adrp x2, g_grace_secs
    add x2, x2, :lo12:g_grace_secs
    str x0, [x2]
    LOG log_warn_clamp_grace, log_warn_clamp_grace_len
    b .env_done
.bad_grace:
    LOG log_warn_bad_grace, log_warn_bad_grace_len
    b .next_env
.next_env:
    add x23, x23, #8
    b .find_env
.env_done:

    // EP_SUBREAPER
    mov x23, x21
.find_subreaper:
    ldr x24, [x23]
    cbz x24, .subreaper_done
    adrp x0, ep_subreaper_pref
    add x0, x0, :lo12:ep_subreaper_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_subreaper_env
    // Check if value is "1"
    ldrb w1, [x0]
    cmp w1, #'1'
    bne .subreaper_done
    ldrb w1, [x0, #1]
    cbnz w1, .subreaper_done
    // Set PR_SET_CHILD_SUBREAPER
    mov x0, #PR_SET_CHILD_SUBREAPER
    mov x1, #1
    mov x2, #0
    mov x3, #0
    mov x4, #0
    SYSCALL SYS_prctl
    b .subreaper_done
.next_subreaper_env:
    add x23, x23, #8
    b .find_subreaper
.subreaper_done:

    // EP_EXIT_CODE_BASE
    mov x23, x21
.find_exit_base:
    ldr x24, [x23]
    cbz x24, .exit_base_done
    adrp x0, ep_exit_base_pref
    add x0, x0, :lo12:ep_exit_base_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_exit_base_env
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .bad_exit_base
    cmp x0, #255
    bgt .range_exit_base
    adrp x2, g_exit_code_base
    add x2, x2, :lo12:g_exit_code_base
    str x0, [x2]
    b .exit_base_done
.range_exit_base:
    LOG log_warn_range_exit_base, log_warn_range_exit_base_len
    b .exit_base_done
.bad_exit_base:
    LOG log_warn_bad_exit_base, log_warn_bad_exit_base_len
    b .next_exit_base_env
.next_exit_base_env:
    add x23, x23, #8
    b .find_exit_base
.exit_base_done:

    // EP_RESTART_ENABLED
    mov x23, x21
.find_restart_enabled:
    ldr x24, [x23]
    cbz x24, .restart_enabled_done
    adrp x0, ep_restart_enabled_pref
    add x0, x0, :lo12:ep_restart_enabled_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_restart_enabled_env
    // Check if value is "1"
    ldrb w1, [x0]
    cmp w1, #'1'
    bne .restart_enabled_done
    ldrb w1, [x0, #1]
    cbnz w1, .restart_enabled_done
    adrp x2, g_restart_enabled
    add x2, x2, :lo12:g_restart_enabled
    mov x3, #1
    str x3, [x2]
    b .restart_enabled_done
.next_restart_enabled_env:
    add x23, x23, #8
    b .find_restart_enabled
.restart_enabled_done:

    // EP_MAX_RESTARTS
    mov x23, x21
.find_max_restarts:
    ldr x24, [x23]
    cbz x24, .max_restarts_done
    adrp x0, ep_max_restarts_pref
    add x0, x0, :lo12:ep_max_restarts_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_max_restarts_env
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .bad_max_restarts
    adrp x2, g_max_restarts
    add x2, x2, :lo12:g_max_restarts
    str x0, [x2]
    b .max_restarts_done
.bad_max_restarts:
    LOG log_warn_bad_max_restarts, log_warn_bad_max_restarts_len
    b .next_max_restarts_env
.next_max_restarts_env:
    add x23, x23, #8
    b .find_max_restarts
.max_restarts_done:

    // EP_RESTART_BACKOFF_SECONDS
    mov x23, x21
.find_restart_backoff:
    ldr x24, [x23]
    cbz x24, .restart_backoff_done
    adrp x0, ep_restart_backoff_pref
    add x0, x0, :lo12:ep_restart_backoff_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_restart_backoff_env
    mov x1, x0
    bl parse_u64_dec_checked
    cbz x1, .bad_backoff
    tbnz x0, #63, .clamp_backoff
    adrp x2, g_restart_backoff
    add x2, x2, :lo12:g_restart_backoff
    str x0, [x2]
    b .restart_backoff_done
.clamp_backoff:
    mov x0, #0x7fffffffffffffff
    adrp x2, g_restart_backoff
    add x2, x2, :lo12:g_restart_backoff
    str x0, [x2]
    LOG log_warn_clamp_backoff, log_warn_clamp_backoff_len
    b .restart_backoff_done
.bad_backoff:
    LOG log_warn_bad_backoff, log_warn_bad_backoff_len
    b .next_restart_backoff_env
.next_restart_backoff_env:
    add x23, x23, #8
    b .find_restart_backoff
.restart_backoff_done:

    // EP_ARM64_FALLBACK (wait4-only path for QEMU flakiness)
    mov x23, x21
.find_arm64_fallback:
    ldr x24, [x23]
    cbz x24, .arm64_fallback_done
    adrp x0, ep_arm64_fallback_pref
    add x0, x0, :lo12:ep_arm64_fallback_pref
    mov x1, x24
    bl prefix_match
    cbz x0, .next_arm64_fallback_env
    ldrb w1, [x0]
    cmp w1, #'1'
    bne .arm64_fallback_done
    ldrb w1, [x0, #1]
    cbnz w1, .arm64_fallback_done
    adrp x2, g_arm64_fallback
    add x2, x2, :lo12:g_arm64_fallback
    mov x3, #1
    str x3, [x2]
    b .arm64_fallback_done
.next_arm64_fallback_env:
    add x23, x23, #8
    b .find_arm64_fallback
.arm64_fallback_done:

    // If fallback enabled, bypass epoll/signalfd and use wait4 only
    adrp x0, g_arm64_fallback
    add x0, x0, :lo12:g_arm64_fallback
    ldr x0, [x0]
    cbz x0, .normal_path
    LOG log_fallback, log_fallback_len
    // spawn child
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    ldr x0, [x0]
    adrp x1, g_envp
    add x1, x1, :lo12:g_envp
    ldr x1, [x1]
    bl do_spawn
    // wait4(-1, &wait_status, 0, NULL)
    bl get_wait_status_ptr
    mov x1, x0
    mov x0, #-1
    mov x2, #0
    mov x3, #0
    SYSCALL SYS_wait4
    bl get_wait_status_ptr
    ldr x0, [x0]
    bl extract_exit_code
    SYSCALL SYS_exit

.normal_path:
    // setup signals
    mov x0, x21
    bl setup_signals_and_fd
    LOG log_after_sfd, log_after_sfd_len
    adrp x1, g_sfd
    add x1, x1, :lo12:g_sfd
    str x0, [x1]

    // epoll create
    bl epoll_create_fd
    adrp x1, g_epfd
    add x1, x1, :lo12:g_epfd
    str x0, [x1]

    LOG log_epoll_add_enter, log_epoll_add_enter_len
    ldr x0, [x1]
    adrp x2, g_sfd
    add x2, x2, :lo12:g_sfd
    ldr x1, [x2]
    bl epoll_add_fd
    LOG log_epoll_add_exit, log_epoll_add_exit_len
    mov x22, x0              // save return value
    // Debug: epoll_add_fd result
    mov x2, x22
    adrp x0, log_epoll_add_result
    add x0, x0, :lo12:log_epoll_add_result
    mov x1, #log_epoll_add_result_len
    bl log_prefix_num
    // If adding signalfd to epoll failed, fall back to blocking wait4
    mov x0, x22              // restore return value
    cmp x0, #0
    bge 1f
    // wait4(-1, &wait_status, 0, NULL)
    mov x0, #-1
    bl get_wait_status_ptr
    mov x1, x0
    mov x2, #0
    mov x3, #0
    SYSCALL SYS_wait4
    bl get_wait_status_ptr
    ldr x0, [x0]
    bl extract_exit_code
    adrp x1, g_child_status
    add x1, x1, :lo12:g_child_status
    str x0, [x1]
    LOG log_sigchld_ok, log_sigchld_ok_len
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit
1:

    // spawn child
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    ldr x0, [x0]
    adrp x1, g_envp
    add x1, x1, :lo12:g_envp
    ldr x1, [x1]
    bl do_spawn
    adrp x2, g_child_pid
    add x2, x2, :lo12:g_child_pid
    str x0, [x2]
    // Debug: child pid
    mov x2, x0
    adrp x0, log_child_pid
    add x0, x0, :lo12:log_child_pid
    mov x1, #log_child_pid_len
    bl log_prefix_num

	.main_loop:
    adrp x0, g_epfd
    add x0, x0, :lo12:g_epfd
    ldr x0, [x0]
    bl epoll_wait_once
    mov x1, #-1
    cmp x0, x1
    beq .main_loop
    mov x19, x0              // ready fd

    adrp x0, g_sfd
    add x0, x0, :lo12:g_sfd
    ldr x0, [x0]
    cmp x19, x0
    bne .check_timer

	    bl read_signalfd_once
	    // On signalfd read errors (EAGAIN/EINTR), ignore and continue.
	    tbnz x0, #63, .main_loop
	    mov x20, x0              // signo
    mov x2, x20
    adrp x0, log_signal_prefix
    add x0, x0, :lo12:log_signal_prefix
    mov x1, #log_signal_prefix_len
    bl log_prefix_num
	    cmp x20, #SIGCHLD
	    beq .handle_chld

	    // If child already exited (e.g. crash + pending restart backoff), avoid
	    // forwarding signals to a potentially reused PGID.
	    adrp x0, g_child_exited
	    add x0, x0, :lo12:g_child_exited
	    ldr x0, [x0]
	    cmp x0, #1
	    bne 1f
	    adrp x1, g_backoff_tfd
	    add x1, x1, :lo12:g_backoff_tfd
	    ldr x1, [x1]
	    cbz x1, 2f
	    // Backoff is active: only shutdown signals cancel the restart; other signals are ignored.
	    cmp x20, #SIGTERM
	    beq 3f
	    cmp x20, #SIGINT
	    beq 3f
	    cmp x20, #SIGHUP
	    beq 3f
	    cmp x20, #SIGQUIT
	    beq 3f
	    LOG log_info_child_exited_ignore_signal, log_info_child_exited_ignore_signal_len
	    b .main_loop
3:
	    LOG log_info_child_exited_cancel_restart, log_info_child_exited_cancel_restart_len
2:
	    adrp x0, g_child_status
	    add x0, x0, :lo12:g_child_status
	    ldr x0, [x0]
	    SYSCALL SYS_exit
1:

    // soft signals
    cmp x20, #SIGTERM
    beq .soft_signal
    cmp x20, #SIGINT
    beq .soft_signal
    cmp x20, #SIGHUP
    beq .soft_signal
    cmp x20, #SIGQUIT
    beq .soft_signal

    // forward others
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    mov x1, x20
    bl forward_signal_to_group
    b .main_loop

.soft_signal:
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    mov x1, x20
    bl forward_signal_to_group

    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    bl reap_children_nonblock
    cbz x0, .after_opportunistic

    bl get_wait_status_ptr
    ldr x0, [x0]
    bl extract_exit_code
    adrp x1, g_child_status
    add x1, x1, :lo12:g_child_status
    str x0, [x1]
    adrp x1, g_child_exited
    add x1, x1, :lo12:g_child_exited
    mov x2, #1
    str x2, [x1]
    LOG log_sigchld_ok, log_sigchld_ok_len
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit

.after_opportunistic:
    // If the main child already exited (e.g., crash + pending restart backoff),
    // treat any shutdown signal as "stop now" and do not restart.
    adrp x0, g_child_exited
    add x0, x0, :lo12:g_child_exited
    ldr x0, [x0]
    cmp x0, #1
    bne .maybe_start_shutdown
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit
	.maybe_start_shutdown:
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    ldr x1, [x0]
    cmp x1, #1
    beq .main_loop
    LOG log_first_soft, log_first_soft_len
    adrp x2, g_grace_secs
    add x2, x2, :lo12:g_grace_secs
    ldr x2, [x2]
    adrp x0, log_grace_secs_prefix
    add x0, x0, :lo12:log_grace_secs_prefix
    mov x1, #log_grace_secs_prefix_len
    mov x3, x2
    mov x2, x3
    bl log_prefix_num
    adrp x0, g_grace_secs
    add x0, x0, :lo12:g_grace_secs
    ldr x0, [x0]
	    bl create_grace_timerfd
	    // If timerfd creation failed, escalate immediately.
	    tbnz x0, #63, .grace_timer_unavailable
	    adrp x1, g_tfd
	    add x1, x1, :lo12:g_tfd
	    str x0, [x1]
    adrp x2, g_epfd
    add x2, x2, :lo12:g_epfd
	    ldr x0, [x2]
	    ldr x1, [x1]
	    bl epoll_add_fd
	    cmp x0, #0
	    bge 1f
	    // epoll add failed -> close timerfd and escalate immediately
	    adrp x0, g_tfd
	    add x0, x0, :lo12:g_tfd
	    ldr x0, [x0]
	    SYSCALL SYS_close
	    adrp x1, g_tfd
	    add x1, x1, :lo12:g_tfd
	    str xzr, [x1]
	    b .grace_timer_unavailable
1:
	    mov x1, #1
	    adrp x0, g_shutdown
	    add x0, x0, :lo12:g_shutdown
	    str x1, [x0]
	    b .main_loop

.grace_timer_unavailable:
    LOG log_warn_grace_timer_unavailable, log_warn_grace_timer_unavailable_len
    mov x1, #1
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    str x1, [x0]
    // Reconcile child state before immediate escalation.
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    bl reap_children_nonblock
    cbnz x0, .timer_reaped_exit
    b .grace_escalate

.check_timer:
    // Check if this is the backoff timer
    adrp x0, g_backoff_tfd
    add x0, x0, :lo12:g_backoff_tfd
    ldr x0, [x0]
    cbz x0, .check_grace_timer
    cmp x19, x0
    bne .check_grace_timer
    // Backoff timer expired -> restart child
    mov x0, x19
    bl read_timerfd_tick
    // Close backoff timerfd
    adrp x0, g_backoff_tfd
    add x0, x0, :lo12:g_backoff_tfd
    ldr x0, [x0]
    SYSCALL SYS_close
    adrp x1, g_backoff_tfd
    add x1, x1, :lo12:g_backoff_tfd
    str xzr, [x1]
    // If shutdown began while we were waiting for backoff, do not restart.
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    ldr x0, [x0]
    cmp x0, #1
    bne 1f
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit
1:
    // Reset state for restart
    adrp x0, g_child_exited
    add x0, x0, :lo12:g_child_exited
    str xzr, [x0]
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    str xzr, [x0]
    adrp x0, g_killed
    add x0, x0, :lo12:g_killed
    str xzr, [x0]
    // Spawn new child
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    ldr x0, [x0]
    adrp x1, g_envp
    add x1, x1, :lo12:g_envp
    ldr x1, [x1]
    bl do_spawn
    adrp x2, g_child_pid
    add x2, x2, :lo12:g_child_pid
    str x0, [x2]
    // Increment restart count
    adrp x0, g_restart_count
    add x0, x0, :lo12:g_restart_count
    ldr x1, [x0]
    add x1, x1, #1
    str x1, [x0]
    mov x2, x1
    adrp x0, log_restart_count_prefix
    add x0, x0, :lo12:log_restart_count_prefix
    mov x1, #log_restart_count_prefix_len
    bl log_prefix_num
    LOG log_restart, log_restart_len
    b .main_loop
.check_grace_timer:
    // timerfd event -> escalate SIGKILL if child not yet exited
    adrp x0, g_tfd
    add x0, x0, :lo12:g_tfd
    ldr x0, [x0]
    cbz x0, .main_loop
    cmp x19, x0
    bne .main_loop

    mov x0, x19
    bl read_timerfd_tick

    // Final reconciliation: the main child may already be waitable while
    // SIGCHLD is still queued on signalfd. Reap before deciding to escalate.
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    bl reap_children_nonblock
    cbnz x0, .timer_reaped_exit

    adrp x0, g_child_exited
    add x0, x0, :lo12:g_child_exited
    ldr x0, [x0]
    cmp x0, #1
    beq .main_loop
.grace_escalate:
    // avoid killing a reused PGID: if kill(-pgid, 0) reports ESRCH, skip escalation
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    neg x0, x0
    mov x1, #0
    SYSCALL SYS_kill
    cmp x0, #0
    bge 1f
    neg x2, x0
    cmp x2, #ESRCH
    bne 1f
    LOG log_escalate_skip_dead_pgid, log_escalate_skip_dead_pgid_len
    b .main_loop
1:
    LOG log_escalate_kill, log_escalate_kill_len
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    mov x1, #SIGKILL
    bl forward_signal_to_group
    mov x1, #1
    adrp x0, g_killed
    add x0, x0, :lo12:g_killed
    str x1, [x0]
    b .main_loop

.timer_reaped_exit:
    bl get_wait_status_ptr
    ldr x0, [x0]
    bl extract_exit_code
    adrp x1, g_child_status
    add x1, x1, :lo12:g_child_status
    str x0, [x1]
    adrp x1, g_child_exited
    add x1, x1, :lo12:g_child_exited
    mov x2, #1
    str x2, [x1]
    LOG log_sigchld_ok, log_sigchld_ok_len
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit

.handle_chld:
    adrp x0, g_child_pid
    add x0, x0, :lo12:g_child_pid
    ldr x0, [x0]
    bl reap_children_nonblock
    cbz x0, .main_loop

    bl get_wait_status_ptr
    ldr x0, [x0]
    bl extract_exit_code
    adrp x1, g_child_status
    add x1, x1, :lo12:g_child_status
    str x0, [x1]
    adrp x1, g_child_exited
    add x1, x1, :lo12:g_child_exited
    mov x2, #1
    str x2, [x1]

    // Check if we should restart (only if restart enabled, not in shutdown, and child was killed by signal)
    adrp x0, g_restart_enabled
    add x0, x0, :lo12:g_restart_enabled
    ldr x0, [x0]
    cmp x0, #1
    bne .no_restart
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    ldr x0, [x0]
    cmp x0, #1
    beq .no_restart
    // Check if child was killed by signal (not normal exit)
    bl get_wait_status_ptr
    ldr x0, [x0]
    and x0, x0, #0x7f
    cbz x0, .no_restart  // Normal exit, don't restart
    // Check max restarts
    adrp x0, g_max_restarts
    add x0, x0, :lo12:g_max_restarts
    ldr x0, [x0]
    cbz x0, .check_restart_backoff  // 0 means unlimited
    adrp x1, g_restart_count
    add x1, x1, :lo12:g_restart_count
    ldr x1, [x1]
    cmp x1, x0
    bge .max_restarts_reached
	.check_restart_backoff:
    // Check if we need backoff
    adrp x0, g_restart_backoff
    add x0, x0, :lo12:g_restart_backoff
    ldr x0, [x0]
    cbz x0, .restart_immediately
    mov x3, x0
    mov x2, x3
    adrp x1, log_restart_backoff_prefix
    add x1, x1, :lo12:log_restart_backoff_prefix
    mov x0, x1
    mov x1, #log_restart_backoff_prefix_len
    bl log_prefix_num
    // Create backoff timerfd
    mov x0, x3
    bl create_grace_timerfd
    adrp x1, g_backoff_tfd
    add x1, x1, :lo12:g_backoff_tfd
    str x0, [x1]
    // Check if timerfd creation failed
    tbnz x0, #63, .restart_immediately  // Negative means error
	    // Add backoff timerfd to epoll
	    adrp x2, g_epfd
	    add x2, x2, :lo12:g_epfd
	    ldr x0, [x2]
	    ldr x1, [x1]
	    bl epoll_add_fd
	    cmp x0, #0
	    bge 1f
	    LOG log_warn_backoff_timer_epoll_failed, log_warn_backoff_timer_epoll_failed_len
	    // close backoff timerfd and restart immediately
	    adrp x0, g_backoff_tfd
	    add x0, x0, :lo12:g_backoff_tfd
	    ldr x0, [x0]
	    SYSCALL SYS_close
	    adrp x1, g_backoff_tfd
	    add x1, x1, :lo12:g_backoff_tfd
	    str xzr, [x1]
	    b .restart_immediately
1:
	    LOG log_backoff_wait, log_backoff_wait_len
	    b .main_loop
.restart_immediately:
    // Reset state for restart
    adrp x0, g_child_exited
    add x0, x0, :lo12:g_child_exited
    str xzr, [x0]
    adrp x0, g_shutdown
    add x0, x0, :lo12:g_shutdown
    str xzr, [x0]
    adrp x0, g_killed
    add x0, x0, :lo12:g_killed
    str xzr, [x0]
    // Spawn new child
    adrp x0, g_argv_exec
    add x0, x0, :lo12:g_argv_exec
    ldr x0, [x0]
    adrp x1, g_envp
    add x1, x1, :lo12:g_envp
    ldr x1, [x1]
    bl do_spawn
    adrp x2, g_child_pid
    add x2, x2, :lo12:g_child_pid
    str x0, [x2]
    // Increment restart count
    adrp x0, g_restart_count
    add x0, x0, :lo12:g_restart_count
    ldr x1, [x0]
    add x1, x1, #1
    str x1, [x0]
    mov x2, x1
    adrp x0, log_restart_count_prefix
    add x0, x0, :lo12:log_restart_count_prefix
    mov x1, #log_restart_count_prefix_len
    bl log_prefix_num
    LOG log_restart, log_restart_len
    b .main_loop
.max_restarts_reached:
    LOG log_max_restarts, log_max_restarts_len
.no_restart:
    adrp x1, g_killed
    add x1, x1, :lo12:g_killed
    ldr x1, [x1]
    cmp x1, #1
    bne .no_force_kill
    adrp x2, g_exit_code_base
    add x2, x2, :lo12:g_exit_code_base
    ldr x2, [x2]
    add x0, x2, #9
    adrp x2, g_child_status
    add x2, x2, :lo12:g_child_status
    str x0, [x2]
.no_force_kill:
    LOG log_sigchld_ok, log_sigchld_ok_len
    adrp x0, g_child_status
    add x0, x0, :lo12:g_child_status
    ldr x0, [x0]
    SYSCALL SYS_exit
