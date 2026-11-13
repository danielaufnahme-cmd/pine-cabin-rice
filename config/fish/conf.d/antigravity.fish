# Antigravity's terminal never answers fish's Primary Device Attribute query,
# so fish stalls 10s at startup. Re-exec once with terminal querying disabled.
# NOTE: fish has no $PPID variable; derive the parent PID from /proc instead
# (an undefined var would make `cat /proc/$PPID/cmdline` run bare `cat`,
# which blocks reading the terminal forever).
if status is-interactive; and not set -q __ag_noquery
    set -l __ag_ppid (string split ' ' -- (string replace -r '^.*\) ' '' < /proc/$fish_pid/stat))[2]
    if test -n "$__ag_ppid"; and test -r /proc/$__ag_ppid/cmdline
        if string match -q '*/Antigravity/*' -- (string split0 < /proc/$__ag_ppid/cmdline)[1]
            set -gx __ag_noquery 1
            exec env fish_features=no-query-term fish
        end
    end
end
