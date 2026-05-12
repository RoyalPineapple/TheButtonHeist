# ThePlant - The Advance Man

> **Files:** `ButtonHeist/Sources/ThePlant/ThePlantAutoStart.m`, `ButtonHeist/Sources/TheInsideJob/Lifecycle/AutoStart.swift`
> **Platform:** iOS 17.0+ (ObjC + Swift)
> **Role:** Zero-configuration auto-initialization - starts TheInsideJob before any app code runs

## Responsibilities

ThePlant enables zero-code-change integration:

1. **ObjC `+load` method** fires automatically when the framework is loaded
2. **Dispatches to main queue** to ensure UIKit safety
3. **Reads configuration** from environment variables and Info.plist
4. **Creates and starts TheInsideJob** singleton before any Swift app code runs
5. **DEBUG builds only** - disabled in Release

## Architecture Diagram

```mermaid
sequenceDiagram
    participant DL as Dynamic Linker
    participant TP as ThePlant (+load)
    participant MQ as Main Queue
    participant AS as TheInsideJob+AutoStart
    participant IJ as TheInsideJob

    DL->>TP: Framework loaded (dyld)
    TP->>MQ: dispatch_async(main)
    MQ->>AS: TheInsideJob_autoStartFromLoad()

    AS->>AS: Check INSIDEJOB_DISABLE
    alt disabled
        AS-->>MQ: return (no-op)
    else enabled
        AS->>AS: Read INSIDEJOB_TOKEN
        AS->>AS: Read INSIDEJOB_ID
        AS->>AS: Read INSIDEJOB_POLLING_INTERVAL
        AS->>AS: Read INSIDEJOB_PORT
        AS->>IJ: TheInsideJob.configure(token:instanceId:port:)
        AS->>IJ: TheInsideJob.shared.start()
        AS->>IJ: TheInsideJob.shared.startPolling(interval:)
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

    subgraph Port["Port Resolution"]
        EnvPort["env: INSIDEJOB_PORT"]
        PlistPort["plist: InsideJobPort"]
        EnvPort -->|priority| PortVal["port (default 0 = any available)"]
        PlistPort -->|fallback| PortVal
    end

    Continue --> Token
    Continue --> ID
    Continue --> Poll
    Continue --> Port
```

## Items Flagged for Review

### LOW PRIORITY

**ObjC `+load` timing**
- `+load` runs very early in the process lifecycle
- The `dispatch_async(dispatch_get_main_queue(), ...)` ensures UIKit is available
- But if the app does significant work before the main run loop starts, there could be a brief window where TheInsideJob isn't ready
- In practice this is fine - the async dispatch runs as soon as the main run loop processes its queue

**`@_cdecl` usage**
- `Extensions/AutoStart.swift` uses `@_cdecl("TheInsideJob_autoStartFromLoad")` to expose a Swift function to ObjC
- This is a stable Swift attribute but not officially documented for public use
- Alternative: could use `@objc` class method, but `@_cdecl` avoids needing an ObjC-visible class

**ThePlant target dependency on TheInsideJob**
- ThePlant imports TheInsideJob as a dependency
- The app links both ThePlant and TheInsideJob
- If ThePlant is included without TheInsideJob, it won't compile (which is correct behavior)
