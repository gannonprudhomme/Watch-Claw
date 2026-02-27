#!/bin/bash
# Minimal Bazel wrapper optimized for LLM context windows.
# Produces compact output: success is one line, failures show only what's needed to debug.
#
# Usage:
#   ./bazel-run.sh build //:WatchClaw
#   ./bazel-run.sh build //:WatchClawPhone
#   ./bazel-run.sh build //Modules/SomeModule
#   ./bazel-run.sh test //Modules/SomeModule:SomeModuleTests
#   ./bazel-run.sh test //...
#   ./bazel-run.sh coverage //Modules/SomeModule:SomeModuleTests
#   ./bazel-run.sh coverage //... --level file
#   ./bazel-run.sh coverage //... --level fn
#   ./bazel-run.sh xcodeproj
#
# Output:
#   Success:  "BUILD SUCCEEDED" or "TESTS PASSED (4 targets)"
#   Failure:  Shows compile errors or test failures with minimal noise
#   Coverage: Shows test results + per-target/file/fn coverage percentages
#   Xcodeproj: Generates Xcode project

set -o pipefail

COMMAND="${1:?Usage: $0 <build|test|coverage|xcodeproj> <target> [bazel args...]}"
shift

# xcodeproj: generate Xcode project
if [[ "$COMMAND" == "xcodeproj" ]]; then
    echo "Generating Xcode project..."
    bazel run //:xcodeproj 2>&1
    echo
    echo "Done! Open WatchClaw.xcodeproj."
    exit 0
fi

if [[ "$COMMAND" != "build" && "$COMMAND" != "test" && "$COMMAND" != "coverage" ]]; then
    echo "Error: first argument must be 'build', 'test', 'coverage', or 'xcodeproj'"
    exit 1
fi

TARGET="${1:?Usage: $0 $COMMAND <target> [bazel args...]}"
shift

# For build commands targeting a Module package (no explicit target name after ':'),
# redirect to the ios_build_test target so it compiles for iOS instead of macOS.
# e.g. "build //Modules/MovieDetails" -> "build //Modules/MovieDetails:MovieDetailsBuild"
ORIGINAL_COMMAND="$COMMAND"
if [[ "$COMMAND" == "build" && "$TARGET" == //Modules/* && "$TARGET" != *:* ]]; then
    MODULE_NAME="${TARGET##*/}"
    TARGET="${TARGET}:${MODULE_NAME}Build"
fi

# For coverage, parse --level flag (target|file|fn, default: file)
COVERAGE_LEVEL="file"
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--level" ]]; then
        COVERAGE_LEVEL="$2"
        shift 2
    else
        EXTRA_ARGS+=("$1")
        shift
    fi
done

TMPLOG=$(mktemp)
trap 'rm -f "$TMPLOG"' EXIT

WAITING_REGEX='^Another command \(pid=[0-9]+\) is running\. Waiting for it to complete on the server \(server_pid=[0-9]+\)\.\.\.$'

run_and_capture() {
    while IFS= read -r line; do
        echo "$line" >> "$TMPLOG"
        if [[ "$line" =~ $WAITING_REGEX ]]; then
            # Emit server-lock wait messages immediately so long waits are obvious.
            echo "$line"
        fi
    done
}

if [[ "$COMMAND" == "coverage" ]]; then
    # Run bazel coverage with flags needed for iOS test coverage
    bazel coverage \
        --noshow_progress \
        --show_result=0 \
        --color=no \
        --curses=no \
        --experimental_use_llvm_covmap \
        --spawn_strategy=standalone \
        --cache_test_results=no \
        --test_env=LCOV_MERGER=/usr/bin/true \
        "$TARGET" "${EXTRA_ARGS[@]}" 2>&1 | run_and_capture
else
    # Run bazel build/test with minimal progress output
    bazel "$COMMAND" \
        --noshow_progress \
        --show_result=0 \
        --color=no \
        --curses=no \
        "$TARGET" "${EXTRA_ARGS[@]}" 2>&1 | run_and_capture
fi

EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    if [[ "$COMMAND" == "build" || "$ORIGINAL_COMMAND" == "build" ]]; then
        echo "BUILD SUCCEEDED"
    else
        # Count passed test targets from Bazel's summary lines
        PASSED_COUNT=$(grep -c "PASSED" "$TMPLOG" 2>/dev/null || echo "0")
        if [[ "$PASSED_COUNT" -gt 0 ]]; then
            echo "TESTS PASSED ($PASSED_COUNT targets)"
        else
            echo "TESTS PASSED"
        fi

        # For coverage, parse LCOV data from coverage.dat files
        if [[ "$COMMAND" == "coverage" ]]; then
            COVERAGE_FILES=$(grep -oE '/[^ ]+/coverage\.dat' "$TMPLOG" 2>/dev/null)

            if [[ -n "$COVERAGE_FILES" ]]; then
                echo
                echo "COVERAGE:"

                while IFS= read -r COV_FILE; do
                    [[ ! -f "$COV_FILE" ]] && continue

                    # Extract target name from path: .../ModuleName/TestName/coverage.dat
                    TARGET_NAME=$(echo "$COV_FILE" | sed 's|/coverage\.dat$||' | awk -F/ '{print $NF}')

                    # Compute target-level summary (excluding test files)
                    TARGET_PCT=$(awk '
                    BEGIN { lf = 0; lh = 0; skip = 0 }
                    /^SF:/ { skip = ($0 ~ /Tests\.swift$/) ? 1 : 0 }
                    /^LF:/ { if (!skip) lf += substr($0, 4) + 0 }
                    /^LH:/ { if (!skip) lh += substr($0, 4) + 0 }
                    END { if (lf > 0) printf "%d", int(lh / lf * 100); else printf "0" }
                    ' "$COV_FILE")

                    echo "${TARGET_NAME}: ${TARGET_PCT}%"

                    # File-level and function-level detail
                    if [[ "$COVERAGE_LEVEL" == "file" || "$COVERAGE_LEVEL" == "fn" ]]; then
                        awk -v level="$COVERAGE_LEVEL" '
                        /^SF:/ {
                            if (fname != "" && fname !~ /Tests\.swift$/) {
                                pct = (flf > 0) ? int(flh / flf * 100) : 0
                                printf "  %s: %d%%\n", fname, pct
                                if (level == "fn" && pct < 100) {
                                    for (i = 1; i <= fnc; i++) {
                                        if (fnh[i] == 0) printf "    %s (line %s)\n", fnn[i], fnl[i]
                                    }
                                }
                            }
                            # Reset for new file
                            full = substr($0, 4)
                            n = split(full, p, "/")
                            fname = p[n]
                            flf = 0; flh = 0; fnc = 0
                            delete fnn; delete fnl; delete fnh
                        }
                        /^FN:/ {
                            fnc++
                            s = substr($0, 4)
                            comma = index(s, ",")
                            fnl[fnc] = substr(s, 1, comma - 1)
                            fnn[fnc] = substr(s, comma + 1)
                            fnh[fnc] = 0
                        }
                        /^FNDA:/ {
                            s = substr($0, 6)
                            comma = index(s, ",")
                            hits = substr(s, 1, comma - 1) + 0
                            nm = substr(s, comma + 1)
                            for (i = 1; i <= fnc; i++) {
                                if (fnn[i] == nm) { fnh[i] = hits; break }
                            }
                        }
                        /^LF:/ { flf = substr($0, 4) + 0 }
                        /^LH:/ { flh = substr($0, 4) + 0 }
                        END {
                            if (fname != "" && fname !~ /Tests\.swift$/) {
                                pct = (flf > 0) ? int(flh / flf * 100) : 0
                                printf "  %s: %d%%\n", fname, pct
                                if (level == "fn" && pct < 100) {
                                    for (i = 1; i <= fnc; i++) {
                                        if (fnh[i] == 0) printf "    %s (line %s)\n", fnn[i], fnl[i]
                                    }
                                }
                            }
                        }
                        ' "$COV_FILE" | swift demangle | grep -v "implicit closure"
                    fi
                done <<< "$COVERAGE_FILES"
            fi
        fi
    fi
else
    # Extract compile errors: lines matching "file.swift:line:col: error:"
    COMPILE_ERRORS=$(grep -E '\.swift:[0-9]+:[0-9]+: error:' "$TMPLOG" | awk '!seen[$0]++')

    # Extract failed/passed test target lines
    FAILED_TARGETS=$(grep -E 'FAILED in [0-9]' "$TMPLOG" | awk '!seen[$0]++' || true)
    PASSED_TARGETS=$(grep -E 'PASSED in [0-9]' "$TMPLOG" | awk '!seen[$0]++' || true)
    BAZEL_FAILURE_LINES=$(grep -E '^(INFO: Invocation ID:|ERROR:|INFO: Elapsed time:|INFO: [0-9]+ process(es)?:)' "$TMPLOG" | awk '!seen[$0]++' || true)

    if [[ "$COMMAND" == "build" || "$ORIGINAL_COMMAND" == "build" ]]; then
        echo "BUILD FAILED"
        if [[ -n "$COMPILE_ERRORS" ]]; then
            echo
            echo "$COMPILE_ERRORS"
        elif [[ -n "$BAZEL_FAILURE_LINES" ]]; then
            echo
            echo "$BAZEL_FAILURE_LINES"
        fi
    else
        # Test command failed — could be build errors, test failures, or both
        if [[ -n "$PASSED_TARGETS" ]]; then
            PASSED_COUNT=$(echo "$PASSED_TARGETS" | wc -l | tr -d ' ')
        else
            PASSED_COUNT=0
        fi
        if [[ -n "$FAILED_TARGETS" ]]; then
            FAILED_COUNT=$(echo "$FAILED_TARGETS" | wc -l | tr -d ' ')
        else
            FAILED_COUNT=0
        fi

        if [[ "$FAILED_COUNT" -eq 0 ]] && [[ "$PASSED_COUNT" -eq 0 ]]; then
            # Build/configuration/analysis failure — no tests ran at all
            echo "BUILD FAILED"
            echo
            if [[ -n "$COMPILE_ERRORS" ]]; then
                echo "$COMPILE_ERRORS"
            elif [[ -n "$BAZEL_FAILURE_LINES" ]]; then
                echo "$BAZEL_FAILURE_LINES"
            else
                echo "No parseable errors found. Full Bazel output follows:"
                cat "$TMPLOG"
            fi
        else
            echo "TESTS FAILED ($FAILED_COUNT failed, $PASSED_COUNT passed)"

            # Show compile errors if any
            if [[ -n "$COMPILE_ERRORS" ]]; then
                echo
                echo "Build errors:"
                echo "$COMPILE_ERRORS"
            fi

            # Show which test targets failed
            if [[ -n "$FAILED_TARGETS" ]]; then
                echo
                echo "Failed targets:"
                echo "$FAILED_TARGETS"
            fi

            # Show test failure output (Bazel wraps it in === separators)
            TEST_OUTPUT=$(awk '/^={70,}$/{found=!found; next} found' "$TMPLOG" | grep -v "^$" | head -100)
            if [[ -n "$TEST_OUTPUT" ]]; then
                echo
                echo "$TEST_OUTPUT"
            fi
        fi
        exit $EXIT_CODE
    fi
fi
