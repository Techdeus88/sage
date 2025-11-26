┌─────────────────┐
│ create_pack()   │
│ - wire tasks    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ vim.pack.add()  │
│ - downloads     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ load() callback         │
│ - pack.installed = true │
│ - emit install:finish   │
│ - lifecycle:run_next()  │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: validate      │ ✅ Required
│ - check name/src    │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: install       │ ✅ Required
│ - verify installed  │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: build         │ ⚙️ Conditional
│ - run build cmd     │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: before_hook   │ ⚙️ Conditional
│ - run before()      │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Loader:run()        │
│ - stage processing  │
│ - emit config:fin   │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: config        │ ✅ Required
│ - run config()      │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Task: after_hook    │ ⚙️ Conditional
│ - run after()       │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ lifecycle:complete  │
└─────────────────────┘

1. create_pack() → TaskSystem.wire_pack()
   └─ Sets up lifecycle with 6 default tasks
   └─ Attaches event listeners

2. vim.pack.add() → load() callback
   └─ pack.installed = true
   └─ emit("pack:install:finish")
   └─ lifecycle:run_next()  ← NEW!
       └─ validate task ✅
       └─ install task ✅
       └─ build task ⚙️ (if build specified)
       └─ before_hook ⚙️ (if before specified)
       └─ [waits for config event]

3. Loader calls pack config
   └─ emit("pack:config:finish")
   └─ lifecycle:run_next() (via event listener)
       └─ config task ⚙️
       └─ after_hook ⚙️
       └─ lifecycle:complete event

4. cleanup()
   └─ TaskSystem.unwire_pack() ← NEW!
   └─ Remove event listeners
   └─ Clear lifecycle references
