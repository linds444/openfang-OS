# OpenFang OS — Default .bashrc for interactive bash sessions

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Source global definitions
[ -f /etc/bashrc ] && . /etc/bashrc
[ -f /etc/profile ] && . /etc/profile

# Prompt: colorful with git branch
__git_branch() {
    git branch 2>/dev/null | grep '^\*' | sed 's/^\* //'
}

_openfang_prompt() {
    local branch
    branch=$(__git_branch)
    if [ -n "$branch" ]; then
        echo -n " (\033[1;33m${branch}\033[0m)"
    fi
}

PS1='\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]$(__git_branch | sed "s/\(.*\)/ (\1)/")$ '

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# Window title
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
    ;;
esac

# Enable color support
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -la --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Safety aliases
alias rm='rm -I --preserve-root'
alias mv='mv -i'
alias cp='cp -i'

# Convenience aliases
alias cls='clear'
alias open='xdg-open'
alias ..='cd ..'
alias ...='cd ../..'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# OpenFang shortcuts
alias ofs='openfang-ctl status'
alias ofa='openfang-ctl agents'
alias ofl='openfang-ctl logs'
alias ofc='openfang-ctl config'

# Enable bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
