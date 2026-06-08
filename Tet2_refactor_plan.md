# Tet2.lua Refactor Plan

File này tổng hợp các lỗi, vấn đề bố cục và hướng viết lại sạch hơn cho `Tét2.lua`.

## Mục tiêu

Không nên tiếp tục vá trực tiếp trên file cũ nếu chưa gom lại kiến trúc. Mục tiêu refactor là:

- Gom state về một nơi duy nhất.
- Tách config khỏi logic.
- Giảm vòng lặp vô hạn chạy song song.
- Tách GUI khỏi logic game.
- Tách movement, game phase, PC scanner, round controller thành các khối riêng.
- Cleanup connection khi reset hoặc tắt script.
- Mỗi module chỉ làm một việc.

## Lỗi cần sửa trước

### 1. `isMoving` bị sai scope

Hiện tại `isMoving` được dùng ở nhiều chỗ trước khi khai báo `local isMoving = false`. Điều này có thể tạo ra hai biến khác nhau: một global ngầm và một local.

Cách sửa:

- Đưa `local isMoving = false` lên đầu file, cùng nhóm state.
- Xóa dòng `local isMoving = false` ở phần Auto Save.
- Đảm bảo toàn bộ script chỉ dùng một biến `isMoving` duy nhất.

### 2. `isFindExitPhase()` return sai trong `pcall`

Nếu `return true` nằm bên trong callback của `pcall`, nó chỉ return khỏi callback đó, không return khỏi hàm `isFindExitPhase()`.

Cách sửa:

- Tạo biến `found = false` bên ngoài `pcall`.
- Trong `pcall`, nếu phát hiện exit phase thì set `found = true`.
- Cuối hàm return `found`.

### 3. Quá nhiều state rải rác

Các biến như `gameOver`, `isHacking`, `isSaving`, `currentPC`, `currentTrigger`, `hasEscaped`, `foundBeast` đang bị sửa bởi nhiều loop khác nhau.

Nên gom lại thành một bảng state trung tâm:

```lua
local State = {
    enabled = false,
    roundState = "Idle",
    isMoving = false,
    isSaving = false,
    isHacking = false,
    currentPC = nil,
    currentTrigger = nil,
    beast = nil,
    hackedPCs = {},
    skippedPCs = {},
}
```

## Kiến trúc đề xuất

Nên chia file thành các section rõ ràng:

```lua
-- Services
-- Config
-- State
-- Logger
-- Connection Manager
-- Character System
-- Game Phase System
-- Movement System
-- PC System
-- Survivor Controller
-- Beast Controller
-- Exit Controller
-- Save Controller
-- GUI
-- Main Loop
```

## Game phase logic

Thay vì mỗi chỗ tự check text như `HACK`, `HEAD START`, `FIND EXIT`, nên tạo một hàm duy nhất:

```lua
local function getGamePhase()
    -- return "Idle", "HeadStart", "Hacking", "Exit", "Ended", hoặc "Unknown"
end
```

Sau đó mọi nơi chỉ dùng:

```lua
if getGamePhase() == "Exit" then
    -- handle exit phase
end
```

Lợi ích:

- Ít bug hơn.
- Dễ sửa khi text trong game đổi.
- Không lặp logic status ở nhiều nơi.

## PC logic

Mỗi PC nên có state riêng:

```lua
pcState[pcId] = {
    attempts = 0,
    done = false,
    skipped = false,
    skipReason = nil,
}
```

Các skip reason nên phân biệt:

- `BeastNearby`
- `NoWorkingTrigger`
- `Timeout`
- `AlreadyDone`
- `InvalidPC`
- `MaxAttempts`

Không nên chỉ dùng một bảng `skippedPCs = {}` đơn giản, vì sẽ không biết tại sao PC bị bỏ qua.

## Hack PC flow nên tách nhỏ

Không nên để một hàm `hackPC()` làm mọi thứ. Nên chia thành:

```lua
isPCCompleted(pc)
findUsableTrigger(pc)
moveToPC(pc)
startPCInteraction(pc, trigger)
monitorPCProgress(pc)
finishPC(pc)
skipPC(pc, reason)
```

Flow gợi ý:

```lua
processPC(pc):
    if isPCCompleted(pc) then markDone(pc)
    else find trigger
    else move
    else interact
    else monitor
    else mark done/skip
```

## Save logic

Auto save hiện tại chạy song song với hack logic, dễ gây race condition.

Nên đổi thành kiểu tạm dừng action hiện tại:

```lua
pauseCurrentAction()
runSaveAction()
resumePreviousAction()
```

Không nên để save loop tự ý chen vào movement/hacking mà không có state trung tâm điều phối.

## Exit logic

`autoExitUnified()` nên tách thành các hàm nhỏ:

```lua
findExits()
isExitOpened(exit)
isExitSafe(exit)
isSomeoneOpening(exit)
waitForExitOpen(exit)
enterExit(exit)
```

Flow nên là:

```lua
for each exit:
    if not safe then continue
    if opened then enter
    else if someone opening then wait
    else open
    if opened then enter
```

## Beast logic

Survivor mode và Beast mode nên tách hoàn toàn:

```lua
if isSelfBeast() then
    runBeastRound()
else
    runSurvivorRound()
end
```

Không nên để Beast logic và Survivor logic sửa chung quá nhiều state.

## Connection cleanup

Nên lưu các connection để cleanup:

```lua
local connections = {}

local function addConnection(conn)
    table.insert(connections, conn)
    return conn
end

local function cleanupConnections()
    for _, conn in ipairs(connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(connections)
end
```

Dùng cho:

- `RunService.Heartbeat`
- `RunService.Stepped`
- GUI button events
- `CharacterAdded`
- property changed signals

## Config

Gom magic number vào một bảng:

```lua
local Config = {
    beastDangerDistance = 30,
    exitDangerDistance = 35,
    hackTick = 0.15,
    doorTimeout = 20,
    saveTimeout = 3,
    jumpInterval = 4,
    tweenSpeed = 35,
}
```

Không nên để các số này rải rác trong nhiều hàm.

## GUI

GUI chỉ nên làm ba việc:

- Bật/tắt script.
- Hiển thị trạng thái.
- Cho chỉnh config.

Không nên để GUI chứa logic round, PC, save hoặc exit.

## Main loop gợi ý

Flow chính nên rõ ràng:

```lua
while true do
    waitUntilEnabled()
    waitForRoundStart()
    resetRoundState()

    if isSelfBeast() then
        runBeastRound()
    else
        runSurvivorRound()
        runExitPhase()
    end

    cleanupRound()
end
```

## Thứ tự refactor nên làm

1. Sửa `isMoving`.
2. Sửa `isFindExitPhase()`.
3. Gom `Config` lên đầu file.
4. Gom state vào một bảng `State`.
5. Tạo `getGamePhase()`.
6. Tạo PC state riêng.
7. Chia nhỏ `hackPC()`.
8. Tách movement helper.
9. Tách save/exit/beast thành controller riêng.
10. Thêm connection cleanup.
11. Dọn biến/function không dùng.
12. Refactor GUI cuối cùng.

## Nhận xét cuối

Script hiện tại có nhiều ý tưởng, nhưng thiếu một state machine trung tâm. Vấn đề lớn nhất không phải là thiếu feature, mà là quá nhiều loop tự quyết định cùng lúc. Khi refactor, hãy ưu tiên làm cho flow rõ ràng trước, sau đó mới thêm lại logic chi tiết.
