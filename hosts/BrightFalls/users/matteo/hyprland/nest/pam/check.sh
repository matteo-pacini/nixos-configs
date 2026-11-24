# Run by pam_exec with no PATH: builtins only. The answer arrives on stdin
# with no terminator.
IFS= read -r -d "" pw || true
[ "$pw" = nest-unlock ]
