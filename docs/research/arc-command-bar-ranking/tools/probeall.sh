#!/bin/zsh
# probeall.sh: the query set, one probe each (runs under the native lock)
P=/tmp/cbr/tools/probe1.sh
$P q1-site-prefix-githu "githu"
$P q1b-site-prefix-yout "yout"
$P q1c-site-prefix-wiki "wiki"
$P q2-open-tab-word "fixture"
$P q3-multiword "best pizza dough recipe"
$P q4-question "how tall is the eiffel tower"
$P q5-command "dark mode"
$P q5b-command "new space"
$P q6-history-title "secondary ref"
$P q6b-history-title "long title"
