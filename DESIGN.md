# cext design

Specification:

```lua
-- Example: 1,1024 (version 1, 1024 line blocks)
version,blockSize -- superblock
{
  "/": {
    "isDir": true,
    "children": ["/dir"],
  },
  "/file": {
    "mode": "todo",
    "blocks": [0, 12],
  }
} -- json inodes, line 2
```

Example:

```lua
1,256
{"/":{"isDir": true,"children":["/file"]},"/file":{"blocks":[0,0]}}
hello, world!
```