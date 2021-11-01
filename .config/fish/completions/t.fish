 complete --command t --no-files -a "( ls -A ~/.config/tmuxinator/*.yml | xargs -n 1 basename | sed 's/.yml//')"
