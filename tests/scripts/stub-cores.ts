// Preload of the run-tests.ts test: makes the launcher see the core count in STUB_CORES.
import os from 'node:os';

os.availableParallelism = () => Number(process.env.STUB_CORES);
