import { StatefulComponent } from 'valdi_core/src/Component';
import { App as CounterApp } from 'tap_counter/TapCounter';

// The "real world" variant of the Valdi counter cell: identical UI, plus a
// synthetic load on the JS THREAD that taps must compete with — every 16 ms
// a ~4 ms chunk of object churn + JSON round-trips (~25% duty cycle), the
// shape of a feed diffing / payload parsing in the background. The identical
// load runs in the React Native twin (App.tsx `busy` mode) so the
// busy-thread comparison is apples-to-apples. Measurement stays native
// (the in-app harness); this file only generates contention.

interface State {}

export class App extends StatefulComponent<object, State> {
  private started = false;

  private startBusyLoop(): void {
    setInterval(() => {
      const t0 = Date.now();
      let acc = 0;
      while (Date.now() - t0 < 4) {
        const arr: { i: number; s: string; v: number }[] = [];
        for (let i = 0; i < 100; i++) {
          arr.push({ i, s: 'item-' + i, v: Math.sqrt(i) });
        }
        acc += (JSON.parse(JSON.stringify(arr)) as unknown[]).length;
      }
      return acc;
    }, 16);
  }

  onRender(): void {
    if (!this.started) {
      this.started = true;
      this.startBusyLoop();
    }
    <CounterApp />;
  }
}
