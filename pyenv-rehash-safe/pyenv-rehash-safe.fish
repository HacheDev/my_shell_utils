function pyenv-rehash-safe
    set -l lockfile "$HOME/.pyenv/.rehash.lock"
    command flock -w 120 $lockfile pyenv rehash
end
