import { StatefulComponent } from 'valdi_core/src/Component';
import { systemFont, systemBoldFont } from 'valdi_core/src/SystemFont';

// The minimal "Tap me" counter — Valdi's cell of the cross-framework benchmark
// (see universal_ui/docs/benchmarks.md). Deliberately behavior-identical to its
// native-Compose, compiled-Swift, wasm, and React Native twins: one label + one
// button, nothing else, so the numbers isolate runtime overhead (here: the native
// Valdi runtime + the JS engine) rather than app content.

interface State {
  count: number;
}

export class App extends StatefulComponent<object, State> {
  state: State = { count: 0 };

  // Stamped on tap, read on the next render — kept off `state` so it never itself
  // triggers a re-render. Mirrors the [native-tap]/[wamr-event] latency logs the
  // other cells emit, so tap->update is measured the same way everywhere.
  private tapAt = 0;

  // Startup content signal: the first render pass has produced the native
  // view tree; the frame presenting it follows. Lets the benchmark verify
  // "Displayed" against actual JS-rendered content (logcat: [valdi-content]).
  private firstRenderLogged = false;

  onRender(): void {
    if (!this.firstRenderLogged) {
      this.firstRenderLogged = true;
      console.log('[valdi-content] first render');
    }
    if (this.state.count > 0 && this.tapAt !== 0) {
      console.log(`[valdi-tap] count=${this.state.count} latency=${Date.now() - this.tapAt}ms`);
    }
    <view
      backgroundColor="white"
      width="100%"
      height="100%"
      flexDirection="column"
      alignItems="center"
      justifyContent="center"
    >
      <label
        color="gray"
        value={`Tapped ${this.state.count} time${this.state.count === 1 ? '' : 's'}`}
        font={systemFont(20)}
        marginBottom={24}
      />
      <view
        backgroundColor="#5A57D6"
        paddingLeft={28}
        paddingRight={28}
        paddingTop={12}
        paddingBottom={12}
        borderRadius={10}
        onTap={() => {
          this.tapAt = Date.now();
          this.setState({ count: this.state.count + 1 });
        }}
      >
        <label color="white" value="Tap me" font={systemBoldFont(17)} />
      </view>
    </view>;
  }
}
