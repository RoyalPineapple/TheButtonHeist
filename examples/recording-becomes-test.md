# Recording Becomes A Test

Recording observes normal runtime evidence and stores only durable semantic
intent.

```bash
buttonheist start_heist --app com.buttonheist.testapp

buttonheist get_interface

buttonheist type_text --text "milk" \
  --label "Search"

buttonheist activate \
  --label "Search" \
  --traits button

buttonheist stop_heist --output search-flow.heist
buttonheist run_heist --path search-flow.heist --junit search-flow.xml
```

The generated `.heist` package stores `manifest.json` and canonical `plan.json`
with semantic action steps and expectations. It does not store reads, failed
actions, setup scrolls for semantic commands, viewport geometry, live object
handles, or capture-local IDs as replay identity.
