#! /bin/bash
# Tests of xlbiff window behavior.

# Depends: xvfb, xauth, xwininfo (in x11-utils), xdotool, metacity
# In Debian, xvfb merely recommends xauth, so we must include xauth dependency.
# In Ubuntu, xvfb depends on xauth.

# Usage:
# test-windowing.sh [--logdir dirname] [--binary path_to_xlbiff]

. $(dirname "$0")/utilities.sh

parse_command_line "$@"

create_test_tmpdir

send_new_mail() {
    echo "New message $current_test_name $RANDOM" >> "$test_tmpdir/mailbox"
}

clear_new_mail() {
    rm -f "$test_tmpdir/mailbox"
}

is_xlbiff_visible() {
    # "  Map State: IsUnMapped" or "  Map State: IsViewable"
    xwininfo -name "$xlbiff_name" 2>/dev/null | grep -q 'Map State: IsViewable'
}

is_xlbiff_invisible() {
    ! is_xlbiff_visible
}

is_xlbiff_running() {
    ps ax | grep "$xlbiff_name" | egrep -v -q 'bash|xvfb|grep'
}

is_xlbiff_not_running() {
    ! is_xlbiff_running
}

does_mailer_action_file_exist() {
    # rm will exit non-0 if the file doesn't exist,
    # but in that case we don't want the error message.
    # Cannot use -f to suppress the error message, because that
    # always exits with status 0.
    rm "$test_tmpdir/mailer" 2>/dev/null
}

send_key() {
    local key="$1"
    if [[ -n "$VERBOSE" ]]; then
        printf '%s: sending key %s to %s\n' "$0" "$key" "$xlbiff_name"
    fi
    # also send keyup in case client thinks key is still down from
    # a previous half-delivered key
    msg=$(xdotool search --name "$xlbiff_name" \
          keyup "$key" keydown "$key" 2>&1)
    keydown_status=$?
    # If the keydown causes the window to unmap, this keyup will fail benignly.
    xdotool search --name "$xlbiff_name" keyup "$key" 2>/dev/null
    if [[ "$keydown_status" != 0 ]]; then
        if [[ -n "$VERBOSE" ]]; then
            printf '%s: send %s to %s status %s\n' "$0" \
                   "$key" "$xlbiff_name" "$keydown_status" "$(echo $msg)"
        fi
        return 1
    fi
}

# Echoes the corner positions
get_window_corners() {
    # perhaps WM moves the window when it first maps
    [[ -n "$USE_WM" ]] && sleep 0.1
    xwininfo -name "$xlbiff_name" | grep Corners:
}

pass_test_if_window_unmoved() {
    if is_window_unmoved "$@"; then
        end_test_with_status pass
    else
        end_test_with_status fail
    fi
}

is_window_unmoved() {
    local top_bottom_all="$1"
    local corners_1="$2"
    check_some_corners "$top_bottom_all" "$corners_1" "$(get_window_corners)"
}

check_some_corners() {
    local top_bottom_all="$1"
    local window_corners_1="$2"
    local window_corners_2="$3"
    local corners ul1 ur1 lr1 ll1 ul2 ur2 lr2 ll2
    read corners ul1 ur1 lr1 ll1 <<<"$window_corners_1"
    read corners ul2 ur2 lr2 ll2 <<<"$window_corners_2"
    local compare1 compare2
    case $top_bottom_all in
        top) compare1="$ul1" ; compare2="$ul2" ;;
        bottom) compare1="$ll1" ; compare2="$ll2" ;;
        all) compare1="$ul1 $ur1 $lr1 $ll1" ; compare2="$ul2 $ur2 $lr2 $ll2" ;;
        *)
            printf '%s: unknown check_some_corners action %q\n' \
                   "$0" "$top_bottom_all" >&2
            exit 2 ;;
    esac
    if [[ "$compare1" != "$compare2" ]]; then
        echo "Before $window_corners_1" >&2
        echo " After $window_corners_2" >&2
    elif [[ -n "$VERBOSE" ]]; then
        echo "Before $window_corners_1"
        echo " After $window_corners_2"
    fi
    if [[ "$compare1" != "$compare2" ]]; then
        echo "$0: $top_bottom_all corners should not have moved" \
             "in test $current_test_name" >&2
        return 1
    fi
}

run_1_variation() {
    local wm="$1"
    local bottom="$2"
    local test_name="$3"
    local test_commands="$4"
    shift 4
    # remaining parameters are passed to xlbiff

    if ! should_run_test "$test_name"; then
        return
    fi
    if [[ "$SKIP_BOTTOM" = "$bottom" ]] || [[ "$SKIP_WM" = "$wm" ]]; then
        return
    fi
    start_test "$test_name($wm,$bottom)"

    local xlbiff_common_args=(
        ${XLBIFF_DEBUG:+-debug}
        -name "$xlbiff_name"
        -file "$test_tmpdir/mailbox"
        -update 0.1
        -scanCommand "cat ${test_tmpdir@Q}/mailbox"
        -mailerCommand "touch ${test_tmpdir@Q}/mailer"
        -xrm
        '*translations: <Key>d: popdown()\n <Key>m: mailer()\n <Key>x: exit()\n'
    )
    local xlbiff_bottom_args=(-geometry +0+0)
    if  [[ "$bottom" == bottom ]]; then
        xlbiff_bottom_args=(-bottom -geometry +0-0)
    fi
    clear_new_mail
    [[ "$wm" = nowm ]] && wm=
    [[ "$bottom" = nobottom ]] && bottom=
    USE_WM=$wm start_xlbiff_under_xvfb \
        "${xlbiff_common_args[@]}" "${xlbiff_bottom_args[@]}" "$@"
    send_new_mail
    loop_for 10 is_xlbiff_visible run_test_variations

    # run the test-specific commands
    USE_WM=$wm BOTTOM=$bottom "$test_commands"

    kill_xvfb
}

run_test_variations() {
    run_1_variation nowm nobottom "$@"
    run_1_variation nowm bottom "$@"
    run_1_variation wm nobottom "$@"
    run_1_variation wm bottom "$@"
}

xlbiff_name=xlbiff-$RANDOM


# perform the requested tests

declare -i num_tests_run=0
declare -i num_tests_passed=0


test_sequence_popdown() {
    send_key "d"
    loop_for 5 is_xlbiff_invisible
    send_new_mail
    loop_for 10 is_xlbiff_visible
    end_test_with_status pass
}
run_test_variations popdown test_sequence_popdown

test_sequence_incmail() {
    echo -n > "$test_tmpdir/mailbox"
    loop_for 10 is_xlbiff_invisible empty_mailbox
    send_new_mail
    loop_for 10 is_xlbiff_visible
    rm "$test_tmpdir/mailbox"
    loop_for 10 is_xlbiff_invisible nonexistent_mailbox
    end_test_with_status pass
}
run_test_variations incmail test_sequence_incmail

test_sequence_moremail() {
    local window_corners_1="$(get_window_corners)"
    send_key "d"
    loop_for 5 is_xlbiff_invisible
    send_new_mail
    loop_for 10 is_xlbiff_visible
    local top_bottom_all
    if [[ -n "$BOTTOM" ]]; then
        # xlbiff at bottom of screen may grow up and to the right,
        # but lower left corner should remain fixed.
        top_bottom_all=bottom
    else
        # xlbiff at top of screen may grow down and to the right,
        # but upper left corner should remain fixed.
        top_bottom_all=top
    fi
    pass_test_if_window_unmoved "$top_bottom_all" "$window_corners_1"
}
run_test_variations moremail test_sequence_moremail

test_sequence_mailer_noinc() {
    local window_corners_1="$(get_window_corners)"

    send_key "m"
    loop_for 5 does_mailer_action_file_exist msg1
    loop_for 5 is_xlbiff_visible msg1
    local window_corners_2="$(get_window_corners)"
    check_some_corners all "$window_corners_1" "$window_corners_2"
    local test_result_1="$?"

    send_key "m"
    loop_for 5 does_mailer_action_file_exist msg2
    loop_for 5 is_xlbiff_visible msg2
    if is_window_unmoved all "$window_corners_2" && ((test_result_1 == 0))
    then
        end_test_with_status pass
    else
        end_test_with_status fail
    fi
}
run_test_variations mailer_noinc test_sequence_mailer_noinc

test_sequence_mailer_inc() {
    send_key "m"
    loop_for 5 does_mailer_action_file_exist
    # there is a race condition, because xlbiff could be trying to pop
    # the window back up here, but we check too fast
    sleep 0.1
    loop_for 5 is_xlbiff_invisible
    send_new_mail
    loop_for 10 is_xlbiff_visible
    end_test_with_status pass
}
run_test_variations mailer_inc test_sequence_mailer_inc \
     -mailerCommand \
     "rm ${test_tmpdir@Q}/mailbox; touch ${test_tmpdir@Q}/mailer"

test_sequence_exit_action() {
    send_key x
    loop_for 5 is_xlbiff_not_running
    xlbiff_pid=
    # This may have killed xvfb, too
    [[ -z "$USE_WM" ]] && xvfb_pid=
    end_test_with_status pass
}
run_test_variations exit_action test_sequence_exit_action

test_sequence_fade() {
    loop_for 30 is_xlbiff_invisible
    send_new_mail
    loop_for 10 is_xlbiff_visible
    end_test_with_status pass
}
run_test_variations fade test_sequence_fade -fade 0.2

test_sequence_refresh() {
    window_corners_1="$(get_window_corners)"
    send_key d
    loop_for 10 is_xlbiff_invisible
    loop_for 30 is_xlbiff_visible
    pass_test_if_window_unmoved all "$window_corners_1"
}
run_test_variations refresh test_sequence_refresh -refresh 0.2


if ((num_tests_run == 0)); then
    echo "$0: NO tests were run" >&2
    exit 1
elif (( num_tests_run == num_tests_passed )); then
    echo "All tests pass: $num_tests_passed/$num_tests_run"
else
    echo "Tests passing: $num_tests_passed/$num_tests_run," \
         "FAILING: $((num_tests_run - num_tests_passed))/$num_tests_run" >&2
    exit 1
fi

exit 0
