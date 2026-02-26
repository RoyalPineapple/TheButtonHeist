# ThePlant - The Advance Man

> **Files:** `ButtonHeist/Sources/ThePlant/ThePlantAutoStart.m`, `ButtonHeist/Sources/InsideJob/InsideJob+AutoStart.swift`
> **Platform:** iOS 17.0+ (ObjC + Swift)
> **Role:** Zero-configuration auto-initialization - starts InsideJob before any app code runs

## Responsibilities

ThePlant enables zero-code-change integration:

1. **ObjC `+load` method** fires automatically when the framework is loaded
2. **Dispatches to main queue** to ensure UIKit safety
3. **Reads configuration** from environment variables and Info.plist
4. **Creates and starts InsideJob** singleton before any Swift app code runs
5. **DEBUG builds only** - disabled in Release

## Architecture Diagram

```mermaid
sequenceDiagram
    participant DL as Dynamic Linker
    participant TP as ThePlant (+load)
    participant MQ as Main Queue
    participant AS as InsideJob+AutoStart
    participant IJ as InsideJob

    DL->>TP: Framework loaded (dyld)
    TP->>MQ: dispatch_async(main)
    MQ->>AS: InsideJob_autoStartFromLoad()

    AS->>AS: Check INSIDEJOB_DISABLE
    alt disabled
        AS-->>MQ: return (no-op)
    else enabled
        AS->>AS: Read INSIDEJOB_TOKEN
        AS->>AS: Read INSIDEJOB_ID
        AS->>AS: Read INSIDEJOB_POLLING_INTERVAL
        AS->>IJ: InsideJob.configure(token:instanceId:)
        AS->>IJ: InsideJob.shared.start()
        AS->>IJ: InsideJob.shared.startPolling(interval:)
    end
```

## Configuration Resolution

```mermaid
flowchart TD
    subgraph Disable["Disable Check"]
        EnvDis["env: INSIDEJOB_DISABLE"]
        PlistDis["plist: InsideJobDisableAutoStart"]
        EnvDis --> Check{"truthy?"}
        PlistDis --> Check
        Check -->|yes| Skip["Skip auto-start"]
        Check -->|no| Continue["Continue"]
    end

    subgraph Token["Token Resolution"]
        EnvToken["env: INSIDEJOB_TOKEN"]
        PlistToken["plist: InsideJobToken"]
        EnvToken -->|priority| TokenVal["token value"]
        PlistToken -->|fallback| TokenVal
    end

    subgraph ID["Instance ID"]
        EnvID["env: INSIDEJOB_ID"]
        PlistID["plist: InsideJobInstanceId"]
        EnvID -->|priority| IDVal["instanceId value"]
        PlistID -->|fallback| IDVal
    end

    subgraph Poll["Polling Interval"]
        EnvPoll["env: INSIDEJOB_POLLING_INTERVAL"]
        PlistPoll["plist: InsideJobPollingInterval"]
        EnvPoll -->|priority| PollVal["interval (default 1.0s)"]
        PlistPoll -->|fallback| PollVal
    end

    Continue --> Token
    Continue --> ID
    Continue --> Poll
```

## Items Flagged for Review

### LOW PRIORITY

**ObjC `+load` timing**
- `+load` runs very early in the process lifecycle
- The `dispatch_async(dispatch_get_main_queue(), ...)` ensures UIKit is available
- But if the app does significant work before the main run loop starts, there could be a brief window where InsideJob isn't ready
- In practice this is fine - the async dispatch runs as soon as the main run loop processes its queue

**`@_cdecl` usage**
- `InsideJob+AutoStart.swift` uses `@_cdecl("InsideJob_autoStartFromLoad")` to expose a Swift function to ObjC
- This is a stable Swift attribute but not officially documented for public use
- Alternative: could use `@objc` class method, but `@_cdecl` avoids needing an ObjC-visible class

**ThePlant target dependency on InsideJob**
- ThePlant imports InsideJob as a dependency
- The app links both ThePlant and InsideJob
- If ThePlant is included without InsideJob, it won't compile (which is correct behavior)
