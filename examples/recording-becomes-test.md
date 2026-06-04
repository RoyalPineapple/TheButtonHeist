# Recording Becomes A Test

Recording observes normal runtime evidence and stores only durable semantic
intent.

```bash
buttonheist start_heist --identifier search-flow --app com.buttonheist.testapp

buttonheist get_interface

buttonheist type_text "milk" \
  --label "Search" \
  --expect '{"type":"element_updated","element":{"label":"Search"},"property":"value","to":"milk"}'

buttonheist activate \
  --label "Search" \
  --traits button \
  --expect '{"type":"screen_changed"}'

buttonheist stop_heist --output search-flow.heist
buttonheist play_heist --input search-flow.heist --junit search-flow.xml
```

The `.heist` fixture stores semantic action steps and expectations. It does not
store reads, failed actions, setup scrolls for semantic commands, viewport
geometry, live object handles, or capture-local IDs as replay identity.

