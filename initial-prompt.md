I need a strategy that will allow me to keep encrypted environment information inside of a .git repository as a very simple poor-man's key vault.
This is going to be used in a small company where we'll have a few different high ranking and trusted people share a password of some sort - I was thinking maybe a generated uuid would be adaquate but I am open to other suggestions.  This will never be stored in the repository.

there would be a file structure like this:

secrets/
  unencrypted/      # .gitignored — never committed
    secrets.yaml
  encrypted/        # committed to git
    secrets.enc.yaml

There would be an assumption that a developer places a file called secrets/unencrypted/sharedkey that has the key needed for decryption.

there will be a simple script secrets/encrypt.sh and secrets/decrypt.sh to make syntax very memorable.

