import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Activity,
  Bot,
  BrainCircuit,
  CheckCircle2,
  Clock,
  Command,
  GitBranch,
  RefreshCw,
  ShieldAlert,
  Settings,
  Users,
  Workflow,
  WifiOff,
  Server,
  CircleDot,
  PlayCircle,
  AlertTriangle,
  Archive,
  Music2,
  Bug,
  MoveRight,
  Radio,
  Waves,
  Sparkles,
  Volume2,
  FileText,
  SlidersHorizontal,
  PauseCircle,
  Mic2
} from 'lucide-react';
import { z } from 'zod';
import { invoke } from '@tauri-apps/api/core';
import './styles.css';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 2, retryDelay: 800, staleTime: 10_000, refetchOnWindowFocus: false } }
});

const StateSchema = z.object({
  generated_at: z.string().optional(),
  counts: z
    .object({ running: z.number().default(0), retrying: z.number().default(0), completed: z.number().default(0) })
    .passthrough()
    .default({ running: 0, retrying: 0, completed: 0 }),
  running: z.array(z.any()).default([]),
  retrying: z.array(z.any()).default([]),
  codex_totals: z
    .object({
      input_tokens: z.number().default(0),
      output_tokens: z.number().default(0),
      total_tokens: z.number().default(0),
      seconds_running: z.number().default(0)
    })
    .passthrough()
    .default({ input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0 }),
  rate_limits: z.any().nullable().optional()
}).passthrough();

const KanbanCardSchema = z.object({
  id: z.string().optional(),
  issue_id: z.string().optional(),
  identifier: z.string().optional(),
  linear_identifier: z.string().optional(),
  title: z.string().optional(),
  state: z.string().optional(),
  status: z.any().optional(),
  operator_status: z.string().optional(),
  operator_summary: z.string().nullable().optional(),
  workspace_path: z.string().nullable().optional(),
  session_id: z.string().nullable().optional(),
  last_event: z.string().nullable().optional(),
  last_message: z.string().nullable().optional(),
  turn_count: z.number().optional(),
  tokens: z.object({ total_tokens: z.number().default(0) }).passthrough().optional(),
  attempt: z.number().optional(),
  due_at: z.string().nullable().optional(),
  error: z.string().nullable().optional(),
  priority: z.number().nullable().optional(),
  labels: z.array(z.any()).optional()
}).passthrough();

const KanbanSchema = z.object({
  generated_at: z.string().optional(),
  columns: z.array(z.object({
    id: z.string(),
    title: z.string(),
    count: z.number().optional(),
    cards: z.array(KanbanCardSchema).default([])
  }).passthrough()).default([]),
  counts: StateSchema.shape.counts.optional(),
  codex_totals: StateSchema.shape.codex_totals.optional(),
  rate_limits: z.any().nullable().optional()
}).passthrough();

type SymphonyState = z.infer<typeof StateSchema>;
type KanbanState = z.infer<typeof KanbanSchema>;
const AgentProfileSchema = z.object({
  id: z.string(),
  name: z.string(),
  role: z.string().default('Agent'),
  profile_key: z.string().default('agent'),
  section: z.string().default('Strings'),
  instrument_name: z.string().default('Violin'),
  enabled: z.boolean().default(true),
  description: z.string().default(''),
  instructions: z.string().default(''),
  model: z.string().default(''),
  workspace_key: z.string().default(''),
  capabilities: z.array(z.string()).default([]),
  max_concurrent_tasks: z.number().default(1),
  status: z.string().default('idle'),
  current_assignments: z.array(z.string()).default([]),
  assignment_policy: z.any().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional()
}).passthrough();
const AgentProfilesResponseSchema = z.object({ profiles: z.array(AgentProfileSchema).default([]) });
type AgentProfile = z.infer<typeof AgentProfileSchema>;
type IdleMusician = {
  id: string;
  profile: AgentProfile;
  agent: string;
  role: string;
  section: string;
  instrumentName: string;
  status: 'idle' | 'disabled';
  movement: 'Intermission · Idle';
  intensity: 10;
};
const WorkflowTemplateSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().default(''),
  tags: z.array(z.string()).default([]),
  required_context: z.array(z.string()).default([]),
  variables: z.array(z.string()).default([])
}).passthrough();
const WorkflowTemplatesSchema = z.object({ ok: z.boolean().optional(), templates: z.array(WorkflowTemplateSchema).default([]) });
const WorkflowValidationSchema = z.object({
  ok: z.boolean().optional(),
  valid: z.boolean().default(false),
  writable: z.boolean().optional(),
  errors: z.array(z.string()).default([]),
  warnings: z.array(z.string()).default([]),
  dispatch: z.object({ ok: z.boolean().default(false), errors: z.array(z.string()).default([]) }).optional(),
  metadata: z.any().optional(),
  content_sha256: z.string().optional()
}).passthrough();
const WorkflowGenerateSchema = z.object({
  ok: z.boolean().optional(),
  draft_id: z.string().optional(),
  filename: z.string().optional(),
  template_id: z.string().optional(),
  content: z.string(),
  validation: WorkflowValidationSchema.optional(),
  review: z.any().optional(),
  provenance: z.any().optional()
}).passthrough();
const WorkflowPreviewSchema = z.object({
  ok: z.boolean().optional(),
  preview: z.object({ frontmatter: z.any().optional(), prompt_template: z.string().optional(), metadata: z.any().optional(), content_sha256: z.string().optional() }).passthrough(),
  validation: WorkflowValidationSchema,
  review: z.any().optional()
}).passthrough();
const WorkflowListSchema = z.object({
  ok: z.boolean().optional(),
  root: z.string().optional(),
  workflows: z.array(z.any()).default([]),
  templates: z.array(WorkflowTemplateSchema).default([])
}).passthrough();

type WorkflowTemplate = z.infer<typeof WorkflowTemplateSchema>;
type WorkflowValidation = z.infer<typeof WorkflowValidationSchema>;
type WorkflowPreview = z.infer<typeof WorkflowPreviewSchema>;
type WorkflowList = z.infer<typeof WorkflowListSchema>;
type Tab = 'console' | 'agents' | 'workflow' | 'safety' | 'settings';
type Card = {
  id: string;
  backendId: string;
  identifier: string;
  title: string;
  column: string;
  status: string;
  agent: string;
  turns: number;
  tokens: number;
  priority?: number;
  message?: string;
  retry?: string;
  movement: string;
  instrumentName: string;
  section: string;
  intensity: number;
  source: 'live';
  raw?: unknown;
};

const columns = ['Ready', 'In Progress', 'Human Review', 'Retry', 'Blocked', 'Done'];
const nav: { id: Tab; label: string; icon: React.ElementType }[] = [
  { id: 'console', label: 'Console', icon: Command },
  { id: 'agents', label: 'Agents', icon: Bot },
  { id: 'workflow', label: 'Workflow', icon: GitBranch },
  { id: 'safety', label: 'Safety', icon: ShieldAlert },
  { id: 'settings', label: 'Settings', icon: Settings }
];

function getApiBase() {
  const saved = localStorage.getItem('symphony.apiBase');
  return saved?.trim() || '';
}

async function api<T>(base: string, path: string, init?: RequestInit, timeoutMs = 7_500): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const headers = init?.body ? { 'content-type': 'application/json' } : undefined;
    const res = await fetch(`${base}${path}`, { signal: controller.signal, headers, ...init });
    if (!res.ok) {
      let detail = `${res.status} ${res.statusText}`;
      try {
        const body = await res.json();
        const message = body?.error?.message || body?.message;
        if (message) detail = `${detail}: ${message}`;
      } catch {
        // keep status text
      }
      throw new Error(detail);
    }
    return res.json();
  } finally {
    clearTimeout(timeout);
  }
}

function useSymphonyState(base: string) {
  return useQuery({
    queryKey: ['state', base],
    queryFn: async () => StateSchema.parse(await api(base, '/api/v1/state')),
    refetchInterval: 7_500
  });
}

function useKanban(base: string) {
  return useQuery({
    queryKey: ['kanban', base],
    queryFn: async () => KanbanSchema.parse(await api(base, '/api/kanban')),
    refetchInterval: 7_500
  });
}

function useAgentProfiles(base: string) {
  return useQuery({
    queryKey: ['agentProfiles', base],
    queryFn: async () => AgentProfilesResponseSchema.parse(await api(base, '/api/agents')).profiles,
    refetchInterval: 15_000
  });
}

function useWorkflowTemplates(base: string) {
  return useQuery({
    queryKey: ['workflowTemplates', base],
    queryFn: async () => WorkflowTemplatesSchema.parse(await api(base, '/api/workflows/templates')).templates,
    refetchInterval: false,
    staleTime: 60_000
  });
}

function useWorkflowFiles(base: string) {
  return useQuery({
    queryKey: ['workflowFiles', base],
    queryFn: async () => WorkflowListSchema.parse(await api(base, '/api/workflows')),
    refetchInterval: false,
    staleTime: 30_000
  });
}

function emptyAgentProfile(): AgentProfile {
  return AgentProfileSchema.parse({
    id: '',
    name: '',
    role: 'Builder',
    profile_key: 'developer',
    section: 'Strings',
    instrument_name: 'Violin',
    enabled: true,
    description: '',
    instructions: '',
    model: '',
    workspace_key: '',
    capabilities: [],
    max_concurrent_tasks: 1,
    status: 'idle',
    current_assignments: []
  });
}

function makeIdleMusicians(profiles: AgentProfile[], liveCards: Card[]): IdleMusician[] {
  const activeNames = new Set(liveCards.map(card => card.agent.toLowerCase()));
  return profiles
    .filter(profile => !activeNames.has(profile.name.toLowerCase()))
    .map(profile => ({
      id: `profile-${profile.id}`,
      profile,
      agent: profile.name,
      role: profile.role,
      section: profile.section,
      instrumentName: profile.instrument_name,
      status: profile.enabled ? 'idle' as const : 'disabled' as const,
      movement: 'Intermission · Idle' as const,
      intensity: 10 as const
    }));
}

function normalizeColumn(title: string) {
  const t = title.toLowerCase();
  if (t.includes('run') || t.includes('progress')) return 'In Progress';
  if (t.includes('retry')) return 'Retry';
  if (t.includes('complete') || t.includes('done')) return 'Done';
  if (t.includes('review')) return 'Human Review';
  if (t.includes('block')) return 'Blocked';
  return title || 'Ready';
}

function liveAgentFor(column: string, status: string) {
  const s = status.toLowerCase();
  if (column === 'Retry' || s.includes('retry')) return 'Backoff Agent';
  if (column === 'Done' || s.includes('complete')) return 'Finisher';
  if (column === 'Blocked' || s.includes('block')) return 'Guardian';
  if (column === 'Human Review' || s.includes('review')) return 'Reviewer';
  if (column === 'In Progress' || s.includes('run') || s.includes('execut')) return 'Builder';
  return 'Planner';
}

function movementFor(column: string, status: string) {
  const s = `${column} ${status}`.toLowerCase();
  if (s.includes('block')) return 'Movement V · Dissonance';
  if (s.includes('retry')) return 'Movement IV · Rehearsal';
  if (s.includes('review')) return 'Movement III · Review Cadenza';
  if (s.includes('done') || s.includes('complete')) return 'Finale · Resolution';
  if (s.includes('progress') || s.includes('run') || s.includes('execut')) return 'Movement II · Implementation';
  return 'Movement I · Overture';
}

function sectionFor(column: string, status: string, labels?: unknown[]) {
  const text = `${column} ${status} ${(labels || []).map(String).join(' ')}`.toLowerCase();
  if (text.includes('test') || text.includes('ci')) return 'Percussion';
  if (text.includes('security') || text.includes('guard') || text.includes('block')) return 'Brass';
  if (text.includes('review')) return 'Piano';
  if (text.includes('research') || text.includes('plan')) return 'Woodwinds';
  if (text.includes('retry')) return 'Timpani';
  if (text.includes('done') || text.includes('complete')) return 'Bells';
  return 'Strings';
}

function instrumentNameFor(section: string, agent: string, status: string) {
  const s = `${section} ${agent} ${status}`.toLowerCase();
  if (s.includes('timpani') || s.includes('retry') || s.includes('percussion')) return 'Timpani';
  if (s.includes('brass') || s.includes('guardian') || s.includes('block')) return 'French Horn';
  if (s.includes('piano') || s.includes('review')) return 'Piano';
  if (s.includes('woodwind') || s.includes('planner')) return 'Clarinet';
  if (s.includes('bell') || s.includes('finish')) return 'Glockenspiel';
  return 'Violin';
}

function intensityFor(tokens: number, turns: number, priority?: number) {
  return Math.min(100, Math.max(10, Math.round(tokens / 90 + turns * 8 + (priority || 0) * 6)));
}

function hashString(input: string) {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function midiToFreq(midi: number) {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

const audioScales = {
  calm: [0, 2, 4, 7, 9],
  active: [0, 2, 3, 5, 7, 9, 10],
  retry: [0, 3, 5, 7, 10],
  blocked: [0, 1, 3, 5, 7, 8, 10]
};

type OrchestraAudioState = { enabled: boolean; ready: boolean; activeVoices: number; error?: string };

function useAgentOrchestra({ enabled, cards, offline }: { enabled: boolean; cards: Card[]; offline: boolean }): OrchestraAudioState {
  const cardsRef = useRef(cards);
  const offlineRef = useRef(offline);
  const ctxRef = useRef<AudioContext | null>(null);
  const masterRef = useRef<GainNode | null>(null);
  const timerRef = useRef<number | null>(null);
  const stepRef = useRef(0);
  const nextTimeRef = useRef(0);
  const [audioState, setAudioState] = useState<OrchestraAudioState>({ enabled, ready: false, activeVoices: 0 });

  useEffect(() => {
    cardsRef.current = cards;
    offlineRef.current = offline;
    setAudioState(prev => ({ ...prev, enabled, activeVoices: Math.min(8, offline ? 0 : cards.length) }));
  }, [cards, enabled, offline]);

  useEffect(() => {
    if (!enabled) {
      if (masterRef.current && ctxRef.current) masterRef.current.gain.linearRampToValueAtTime(0.0001, ctxRef.current.currentTime + 0.25);
      if (timerRef.current) window.clearInterval(timerRef.current);
      timerRef.current = null;
      setAudioState(prev => ({ ...prev, enabled: false, ready: Boolean(ctxRef.current), activeVoices: 0 }));
      return;
    }

    try {
      const AudioCtor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioCtor) throw new Error('Web Audio is not available in this browser');
      const ctx = ctxRef.current || new AudioCtor();
      ctxRef.current = ctx;
      if (!masterRef.current) {
        const master = ctx.createGain();
        const compressor = ctx.createDynamicsCompressor();
        compressor.threshold.value = -18;
        compressor.knee.value = 18;
        compressor.ratio.value = 3;
        compressor.attack.value = 0.01;
        compressor.release.value = 0.25;
        master.gain.value = 0.0001;
        master.connect(compressor).connect(ctx.destination);
        masterRef.current = master;
      }
      void ctx.resume();
      masterRef.current.gain.cancelScheduledValues(ctx.currentTime);
      masterRef.current.gain.linearRampToValueAtTime(0.16, ctx.currentTime + 0.35);
      nextTimeRef.current = ctx.currentTime + 0.05;
      if (timerRef.current) window.clearInterval(timerRef.current);
      timerRef.current = window.setInterval(() => scheduleOrchestra(ctx, masterRef.current!, cardsRef, offlineRef, stepRef, nextTimeRef), 30);
      setAudioState({ enabled: true, ready: true, activeVoices: Math.min(8, cardsRef.current.length) });
    } catch (err) {
      setAudioState({ enabled: false, ready: false, activeVoices: 0, error: err instanceof Error ? err.message : String(err) });
    }

    return () => {
      if (timerRef.current) window.clearInterval(timerRef.current);
      timerRef.current = null;
    };
  }, [enabled]);

  return audioState;
}

function scheduleOrchestra(
  ctx: AudioContext,
  out: AudioNode,
  cardsRef: React.MutableRefObject<Card[]>,
  offlineRef: React.MutableRefObject<boolean>,
  stepRef: React.MutableRefObject<number>,
  nextTimeRef: React.MutableRefObject<number>
) {
  const stepDur = 60 / 88 / 2;
  while (nextTimeRef.current < ctx.currentTime + 0.14) {
    const cards = offlineRef.current ? [] : prioritizeCards(cardsRef.current).slice(0, 8);
    if (cards.length) {
      const hasBlocked = cards.some(card => card.column === 'Blocked');
      const hasRetry = cards.some(card => card.column === 'Retry');
      const scale = hasBlocked ? audioScales.blocked : hasRetry ? audioScales.retry : cards.some(card => card.column === 'In Progress') ? audioScales.active : audioScales.calm;
      cards.forEach((card, index) => scheduleCardVoice(ctx, out, card, index, cards.length, scale, stepRef.current, nextTimeRef.current));
    }
    stepRef.current += 1;
    nextTimeRef.current += stepDur;
  }
}

function prioritizeCards(cards: Card[]) {
  const weight = (card: Card) => ({ Blocked: 0, Retry: 1, 'In Progress': 2, 'Human Review': 3, Ready: 4, Done: 5 }[card.column] ?? 6);
  return [...cards].sort((a, b) => weight(a) - weight(b));
}

function scheduleCardVoice(ctx: AudioContext, out: AudioNode, card: Card, index: number, total: number, scale: number[], step: number, time: number) {
  const spec = synthSpec(card);
  if (!shouldPlay(spec.rhythm, step, index)) return;
  const seed = hashString(card.backendId || card.id);
  const degree = (step + index * 2 + seed) % scale.length;
  const harmony = [0, 2, 4, 7][index % 4];
  const octave = spec.octave * 12;
  const midi = 36 + octave + scale[(degree + harmony) % scale.length] + Math.floor((degree + harmony) / scale.length) * 12;
  const pan = total <= 1 ? 0 : -0.7 + (index / (total - 1)) * 1.4;
  playSynthNote(ctx, out, { time, freq: midiToFreq(midi), duration: spec.duration, gain: spec.gain, type: spec.type, filterHz: spec.filterHz, pan });
  if (spec.rhythm === 'cadence' && step % 8 === 0) playSynthNote(ctx, out, { time: time + 0.12, freq: midiToFreq(midi + 7), duration: 0.45, gain: spec.gain * 0.7, type: 'sine', filterHz: 6000, pan });
}

function synthSpec(card: Card) {
  const s = `${card.column} ${card.status} ${card.agent}`.toLowerCase();
  if (s.includes('block') || s.includes('guardian')) return { type: 'triangle' as OscillatorType, octave: 2, gain: 0.026, duration: 0.7, filterHz: 420, rhythm: 'drone' };
  if (s.includes('retry') || s.includes('backoff')) return { type: 'sawtooth' as OscillatorType, octave: 3, gain: 0.028, duration: 0.16, filterHz: 900, rhythm: 'retry' };
  if (s.includes('review')) return { type: 'triangle' as OscillatorType, octave: 4, gain: 0.024, duration: 0.32, filterHz: 2400, rhythm: 'review' };
  if (s.includes('done') || s.includes('finish')) return { type: 'sine' as OscillatorType, octave: 5, gain: 0.024, duration: 0.42, filterHz: 6000, rhythm: 'cadence' };
  if (s.includes('progress') || s.includes('run') || s.includes('builder')) return { type: 'square' as OscillatorType, octave: 4, gain: 0.022, duration: 0.13, filterHz: 1700, rhythm: 'arpeggio' };
  return { type: 'sine' as OscillatorType, octave: 4, gain: 0.014, duration: 0.22, filterHz: 3000, rhythm: 'sparse' };
}

function shouldPlay(rhythm: string, step: number, index: number) {
  if (rhythm === 'drone') return step % 8 === index % 4;
  if (rhythm === 'retry') return step % 3 === index % 3;
  if (rhythm === 'review') return step % 4 === index % 2;
  if (rhythm === 'cadence') return step % 8 === index % 2;
  if (rhythm === 'arpeggio') return step % 2 === index % 2;
  return step % 6 === index % 6;
}

function playSynthNote(ctx: AudioContext, out: AudioNode, opts: { time: number; freq: number; duration: number; gain: number; type: OscillatorType; filterHz: number; pan: number }) {
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  const filter = ctx.createBiquadFilter();
  const pan = ctx.createStereoPanner();
  osc.type = opts.type;
  osc.frequency.setValueAtTime(opts.freq, opts.time);
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(opts.filterHz, opts.time);
  amp.gain.setValueAtTime(0.0001, opts.time);
  amp.gain.exponentialRampToValueAtTime(Math.max(0.0002, opts.gain), opts.time + 0.018);
  amp.gain.exponentialRampToValueAtTime(0.0001, opts.time + opts.duration + 0.09);
  pan.pan.setValueAtTime(opts.pan, opts.time);
  osc.connect(filter).connect(amp).connect(pan).connect(out);
  osc.start(opts.time);
  osc.stop(opts.time + opts.duration + 0.14);
  osc.onended = () => { osc.disconnect(); filter.disconnect(); amp.disconnect(); pan.disconnect(); };
}

function makeCardsFromKanban(kanban?: KanbanState): Card[] {
  if (!kanban) return [];

  return kanban.columns.flatMap(column =>
    column.cards.map((raw, i) => {
      const backendId = raw.issue_id || raw.id || raw.linear_identifier || raw.identifier || `${column.id}-${i}`;
      const identifier = raw.linear_identifier || raw.identifier || backendId;
      const status = String(raw.operator_status || raw.status || raw.last_event || raw.state || column.id || 'ready');
      const normalizedColumn = normalizeColumn(column.title || column.id);

      const turns = raw.turn_count || raw.attempt || 0;
      const tokens = raw.tokens?.total_tokens || 0;
      const priority = raw.priority ?? undefined;
      const agent = liveAgentFor(normalizedColumn, status);
      const section = sectionFor(normalizedColumn, status, raw.labels);

      return {
        id: `${column.id}-${backendId}`,
        backendId,
        identifier,
        title: raw.title || raw.operator_summary || raw.last_message || raw.error || 'Agent session',
        column: normalizedColumn,
        status,
        agent,
        turns,
        tokens,
        priority,
        message: raw.operator_summary || raw.last_message || raw.error || undefined,
        retry: raw.due_at || undefined,
        movement: movementFor(normalizedColumn, status),
        instrumentName: instrumentNameFor(section, agent, status),
        section,
        intensity: intensityFor(tokens, turns, priority),
        source: 'live' as const,
        raw
      };
    })
  );
}


type CodexAuthPayload = {
  available?: boolean;
  authenticated?: boolean;
  status?: string;
  message?: string;
  version?: string;
  command?: string;
  login_command?: string;
  stdout?: string;
  stderr?: string;
  error?: string;
  [key: string]: unknown;
};


type BackendRuntimePayload = {
  baseUrl?: string;
  host?: string;
  port?: number;
  source?: string;
  healthy?: boolean;
  managed?: boolean;
  pid?: number | null;
  logPath?: string | null;
  lastError?: string | null;
  [key: string]: unknown;
};

function useBackendRuntime() {
  return useQuery({
    queryKey: ['backendRuntime'],
    queryFn: async () => invoke<BackendRuntimePayload>('backend_status'),
    refetchInterval: 3_000,
    retry: 1
  });
}

function useCodexAuth(base: string) {
  return useQuery({
    queryKey: ['codexAuth', base],
    queryFn: async () => api<CodexAuthPayload>(base, '/api/codex/auth/status', undefined, 7_500),
    refetchInterval: 20_000
  });
}


function App() {
  const [tab, setTab] = useState<Tab>('console');
  const [base, setBase] = useState(getApiBase());
  const state = useSymphonyState(base);
  const kanban = useKanban(base);
  const profilesQuery = useAgentProfiles(base);
  const codexAuth = useCodexAuth(base);
  const backendRuntime = useBackendRuntime();
  const [debugPayload, setDebugPayload] = useState<string | null>(null);
  const [selectedCardId, setSelectedCardId] = useState<string | null>(null);
  const cards = useMemo(() => makeCardsFromKanban(kanban.data), [kanban.data]);
  const profiles = profilesQuery.data || [];
  const idleMusicians = useMemo(() => makeIdleMusicians(profiles, cards), [profiles, cards]);
  const hasLiveBackendData = Boolean(state.data && kanban.data);
  const hasPollingError = state.isError || kanban.isError;
  const offline = hasPollingError && !hasLiveBackendData;
  const reconnecting = hasPollingError && hasLiveBackendData;
  const [audioEnabled, setAudioEnabled] = useState(false);
  const orchestraAudio = useAgentOrchestra({ enabled: audioEnabled, cards, offline });
  const selectedCard = cards.find(card => card.id === selectedCardId) || cards[0];

  useEffect(() => {
    const saved = localStorage.getItem('symphony.apiBase');
    if (saved && saved.trim()) return;
    invoke<BackendRuntimePayload>('ensure_backend_ready')
      .then(status => {
        if (status?.baseUrl) setBase(status.baseUrl);
      })
      .catch(() => {
        // Browser/Vite dev mode uses the same-origin proxy when no Tauri bridge is present.
      });
  }, []);

  useEffect(() => {
    if (selectedCardId && cards.some(card => card.id === selectedCardId)) return;
    setSelectedCardId(cards[0]?.id ?? null);
  }, [cards, selectedCardId]);

  const invalidateLiveData = () => {
    queryClient.invalidateQueries({ queryKey: ['state', base] });
    queryClient.invalidateQueries({ queryKey: ['kanban', base] });
  };
  const refresh = useMutation({
    mutationFn: () => api(base, '/api/v1/refresh', { method: 'POST', body: '{}' }),
    onSuccess: invalidateLiveData
  });
  const debugIssue = useMutation({
    mutationFn: (id: string) => api(base, `/api/issues/${encodeURIComponent(id)}/debug`),
    onSuccess: payload => setDebugPayload(JSON.stringify(payload, null, 2))
  });
  const moveIssue = useMutation({
    mutationFn: ({ id, target }: { id: string; target: string }) =>
      api(base, `/api/issues/${encodeURIComponent(id)}/move`, { method: 'POST', body: JSON.stringify({ target }) }),
    onSuccess: invalidateLiveData
  });
  const issueAction = useMutation({
    mutationFn: ({ id, action }: { id: string; action: string }) =>
      api(base, `/api/issues/${encodeURIComponent(id)}/actions/${encodeURIComponent(action)}`, { method: 'POST', body: '{}' }),
    onSuccess: invalidateLiveData
  });
  const saveAgentProfile = useMutation({
    mutationFn: (profile: AgentProfile) => {
      const body = JSON.stringify(profile);
      return profile.id
        ? api(base, `/api/agents/${encodeURIComponent(profile.id)}`, { method: 'PATCH', body })
        : api(base, '/api/agents', { method: 'POST', body });
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['agentProfiles', base] })
  });
  const deleteAgentProfile = useMutation({
    mutationFn: (id: string) => api(base, `/api/agents/${encodeURIComponent(id)}`, { method: 'DELETE' }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['agentProfiles', base] })
  });
  const startCodexLogin = useMutation({
    mutationFn: () => api<CodexAuthPayload>(base, '/api/codex/auth/login/start', { method: 'POST', body: '{}' }, 15_000),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['codexAuth', base] })
  });
  const checkCodexAuth = useMutation({
    mutationFn: () => api<CodexAuthPayload>(base, '/api/codex/auth/check', { method: 'POST', body: '{}' }, 10_000),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['codexAuth', base] })
  });
  const logoutCodex = useMutation({
    mutationFn: () => api<CodexAuthPayload>(base, '/api/codex/auth/logout', { method: 'POST', body: '{}' }, 10_000),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['codexAuth', base] })
  });
  const startBundledBackend = useMutation({
    mutationFn: () => invoke<BackendRuntimePayload>('ensure_backend_ready'),
    onSuccess: status => {
      if (status?.baseUrl) setBase(status.baseUrl);
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
      invalidateLiveData();
    }
  });
  const restartBundledBackend = useMutation({
    mutationFn: () => invoke<BackendRuntimePayload>('backend_restart'),
    onSuccess: status => {
      if (status?.baseUrl) setBase(status.baseUrl);
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
      invalidateLiveData();
    }
  });
  const backendLogs = useMutation({
    mutationFn: () => invoke<{ logPath?: string; text: string }>('backend_logs', { maxBytes: 65536 })
  });
  const saveBase = (v: string) => {
    localStorage.setItem('symphony.apiBase', v);
    setBase(v.trim());
    queryClient.invalidateQueries();
  };

  const actionBusy = refresh.isPending || debugIssue.isPending || moveIssue.isPending || issueAction.isPending || saveAgentProfile.isPending || deleteAgentProfile.isPending || startCodexLogin.isPending || checkCodexAuth.isPending || logoutCodex.isPending || startBundledBackend.isPending || restartBundledBackend.isPending;

  return (
    <div className="concertShell">
      <aside className="conductorSidebar pixelPanel">
        <div className="brandLockup">
          <div className="brandMark"><Music2 size={20} /></div>
          <div>
            <strong>Symphony</strong>
            <span>Conductor Console</span>
          </div>
        </div>
        <nav className="tabs" aria-label="Primary">
          {nav.map(n => {
            const Icon = n.icon;
            return (
              <button key={n.id} className={tab === n.id ? 'tab active' : 'tab'} onClick={() => setTab(n.id)}>
                <Icon size={17} />
                <span>{n.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="maestroCard">
          <PixelPortrait role="maestroPortrait" label="MC" />
          <div>
            <b>Maestro</b>
            <span>{offline ? 'awaiting orchestra' : reconnecting ? 'holding last cue' : 'conducting live'}</span>
          </div>
        </div>
        <div className="sidebarFooter">
          <span className={offline ? 'statusDot offline' : reconnecting ? 'statusDot reconnecting' : 'statusDot online'} />
          {offline ? 'Backend unavailable' : reconnecting ? 'Reconnecting… live cache held' : 'Connected via API'}
        </div>
      </aside>

      <main className="concertWorkspace">
        <ConcertHeader
          offline={offline}
          reconnecting={reconnecting}
          onRefresh={() => refresh.mutate()}
          busy={refresh.isPending}
          audioEnabled={audioEnabled}
          onToggleAudio={() => setAudioEnabled(value => !value)}
          orchestraAudio={orchestraAudio}
        />
        <MetricsStrip state={state.data} online={!offline} reconnecting={reconnecting} />
        {offline && <OfflineBanner base={base} />}
        {reconnecting && <ReconnectBanner base={base} />}
        <section className="contentArea" aria-live="polite">
          {tab === 'console' && (
            <OrchestraFloor
              cards={cards}
              selectedCard={selectedCard}
              selectedCardId={selectedCardId}
              setSelectedCardId={setSelectedCardId}
              idleMusicians={idleMusicians}
              debugPayload={debugPayload}
              busy={actionBusy}
              onDebug={id => debugIssue.mutate(id)}
              onMove={(id, target) => moveIssue.mutate({ id, target })}
              orchestraAudio={orchestraAudio}
              onAction={(id, action) => issueAction.mutate({ id, action })}
            />
          )}
          {tab === 'agents' && (
            <Agents
              cards={cards}
              profiles={profiles}
              idleMusicians={idleMusicians}
              loading={profilesQuery.isLoading}
              busy={actionBusy}
              setSelectedCardId={setSelectedCardId}
              onSaveProfile={profile => saveAgentProfile.mutate(profile)}
              onDeleteProfile={id => deleteAgentProfile.mutate(id)}
            />
          )}
          {tab === 'workflow' && <WorkflowPanel base={base} state={state.data} cards={cards} />}
          {tab === 'safety' && <SafetyPanel />}
          {tab === 'settings' && (
            <SettingsPanel
              base={base}
              saveBase={saveBase}
              codexAuth={codexAuth.data}
              codexLoading={codexAuth.isLoading}
              codexError={codexAuth.error instanceof Error ? codexAuth.error.message : codexAuth.isError ? 'Unable to reach Codex auth endpoint.' : undefined}
              codexBusy={startCodexLogin.isPending || checkCodexAuth.isPending || logoutCodex.isPending}
              backendRuntime={backendRuntime.data}
              backendRuntimeError={backendRuntime.error instanceof Error ? backendRuntime.error.message : backendRuntime.isError ? 'Tauri backend manager unavailable in browser/dev mode.' : undefined}
              backendBusy={startBundledBackend.isPending || restartBundledBackend.isPending}
              backendLogs={backendLogs.data}
              onStartBackend={() => startBundledBackend.mutate()}
              onRestartBackend={() => restartBundledBackend.mutate()}
              onRefreshBackend={() => queryClient.invalidateQueries({ queryKey: ['backendRuntime'] })}
              onLoadBackendLogs={() => backendLogs.mutate()}
              onStartCodexLogin={() => startCodexLogin.mutate()}
              onCheckCodex={() => checkCodexAuth.mutate()}
              onLogoutCodex={() => logoutCodex.mutate()}
            />
          )}
        </section>
      </main>

      <InspectorRail
        cards={cards}
        selectedCard={selectedCard}
        debugPayload={debugPayload}
        busy={actionBusy}
        onSelect={setSelectedCardId}
        onDebug={id => debugIssue.mutate(id)}
        onMove={(id, target) => moveIssue.mutate({ id, target })}
        onAction={(id, action) => issueAction.mutate({ id, action })}
      />
    </div>
  );
}

function ConcertHeader({
  offline,
  reconnecting,
  onRefresh,
  busy,
  audioEnabled,
  onToggleAudio,
  orchestraAudio
}: {
  offline: boolean;
  reconnecting: boolean;
  onRefresh: () => void;
  busy: boolean;
  audioEnabled: boolean;
  onToggleAudio: () => void;
  orchestraAudio: OrchestraAudioState;
}) {
  return (
    <header className="concertHeader pixelPanel">
      <div>
        <p className="eyebrow">Live score for autonomous work</p>
        <h1>Conductor View</h1>
        <p className="subtle">{offline ? 'The pit is quiet until the backend returns' : reconnecting ? 'Holding the last live score while the backend reconnects' : 'Real Linear issues conducted by Codex agents'} · musicians, movements, and generated score</p>
      </div>
      <div className="actions">
        <span className={`pill audioPill ${audioEnabled ? 'active' : 'neutral'}`} title={orchestraAudio.error || 'Generated from live agent cards'}>
          <Waves size={14} /> {audioEnabled ? `${orchestraAudio.activeVoices} voices` : 'orchestra muted'}
        </span>
        <button className={audioEnabled ? 'button primary' : 'button secondary'} onClick={onToggleAudio}>
          {audioEnabled ? <PauseCircle size={16} /> : <Volume2 size={16} />}
          {audioEnabled ? 'Mute Music' : 'Enable Music'}
        </button>
        <button className="button primary" onClick={onRefresh} disabled={busy}><RefreshCw size={16} />Cue Linear Poll</button>
      </div>
    </header>
  );
}

function MetricsStrip({ state, online, reconnecting }: { state?: SymphonyState; online: boolean; reconnecting?: boolean }) {
  const metrics = [
    { value: reconnecting ? 'Holding' : online ? 'Live' : 'Silent', label: 'House', icon: Radio },
    { value: state?.counts.running ?? 0, label: 'Playing', icon: Volume2 },
    { value: state?.counts.retrying ?? 0, label: 'Retuning', icon: Clock },
    { value: state?.counts.completed ?? 0, label: 'Finale', icon: CheckCircle2 },
    { value: state?.codex_totals.total_tokens ?? 0, label: 'Notes', icon: Waves }
  ];
  return (
    <section className="metrics scoreMetrics">
      {metrics.map(({ value, label, icon: Icon }) => (
        <div className="metric pixelPanel" key={label}>
          <div className="metricIcon"><Icon size={18} /></div>
          <span>{label}</span>
          <strong>{typeof value === 'number' ? value.toLocaleString() : value}</strong>
        </div>
      ))}
    </section>
  );
}

function OfflineBanner({ base }: { base: string }) {
  return (
    <div className="banner pixelPanel">
      <WifiOff size={18} />
      <span>Backend unavailable at <code>{base || 'same-origin Vite proxy / awaiting Tauri default'}</code>. No placeholder data is displayed.</span>
    </div>
  );
}

function ReconnectBanner({ base }: { base: string }) {
  return (
    <div className="banner reconnectBanner pixelPanel">
      <Radio size={18} />
      <span>Backend heartbeat missed at <code>{base || 'same-origin Vite proxy / awaiting Tauri default'}</code>; holding the last live score while reconnecting.</span>
    </div>
  );
}

const stationMeta = [
  { column: 'Ready', id: 'queue', label: 'Score Queue', kind: 'queue', x: 17, y: 70 },
  { column: 'In Progress', id: 'strings', label: 'Strings / Active', kind: 'active', x: 38, y: 36 },
  { column: 'Human Review', id: 'podium', label: 'Conductor Review', kind: 'review', x: 61, y: 35 },
  { column: 'Retry', id: 'tuning', label: 'Tuning Retry', kind: 'retry', x: 76, y: 68 },
  { column: 'Blocked', id: 'dissonance', label: 'Dissonance', kind: 'blocked', x: 24, y: 39 },
  { column: 'Done', id: 'finale', label: 'Finale Archive', kind: 'done', x: 86, y: 82 }
];

function OrchestraFloor({
  cards,
  selectedCard,
  selectedCardId,
  setSelectedCardId,
  idleMusicians,
  debugPayload,
  busy,
  onDebug,
  onMove,
  orchestraAudio,
  onAction
}: {
  cards: Card[];
  selectedCard?: Card;
  selectedCardId: string | null;
  setSelectedCardId: (id: string) => void;
  idleMusicians: IdleMusician[];
  debugPayload: string | null;
  busy: boolean;
  onDebug: (id: string) => void;
  onMove: (id: string, target: string) => void;
  orchestraAudio: OrchestraAudioState;
  onAction: (id: string, action: string) => void;
}) {
  const counts = Object.fromEntries(stationMeta.map(station => [station.column, cards.filter(card => card.column === station.column).length]));
  const movements = movementSummary(cards);

  return (
    <div className="orchestraDeck">
      <section className="stageMap pixelPanel" aria-label="Animated orchestra floor">
        <div className="stageBackdrop" aria-hidden="true">
          <div className="backWall"><span className="window" /><span className="window" /><span className="poster">♬ CODEX HALL</span></div>
          <div className="stageFloor" />
          <div className="pitRail" />
        </div>
        <MovementRibbon movements={movements} activeVoices={orchestraAudio.activeVoices} />
        <Conductor active={cards.length > 0} />
        <CueLines cards={cards} />
        {stationMeta.map(station => (
          <Station key={station.id} station={station} count={counts[station.column] || 0} />
        ))}
        {cards.length === 0 && <EmptyHouse />}
        {cards.map((card, index) => {
          const station = stationMeta.find(item => item.column === card.column) || stationMeta[0];
          return (
            <PerformerCard
              key={card.id}
              card={card}
              index={index}
              station={station}
              selected={selectedCardId === card.id}
              busy={busy}
              onSelect={() => setSelectedCardId(card.id)}
              onDebug={() => onDebug(card.backendId)}
              onMove={() => onMove(card.backendId, 'Done')}
              onRetry={() => onAction(card.backendId, 'retry')}
              onArchive={() => onAction(card.backendId, 'archive')}
            />
          );
        })}
        {idleMusicians.map((musician, index) => <IdleMusicianCard key={musician.id} musician={musician} index={index} />)}
        <FloatingNotes cards={cards} />
      </section>
      <ScoreConsole
        selectedCard={selectedCard}
        debugPayload={debugPayload}
        busy={busy}
        onDebug={onDebug}
        onMove={onMove}
        onAction={onAction}
      />
    </div>
  );
}

function movementSummary(cards: Card[]) {
  const grouped = new Map<string, Card[]>();
  cards.forEach(card => grouped.set(card.movement, [...(grouped.get(card.movement) || []), card]));
  return Array.from(grouped.entries()).map(([movement, items]) => ({ movement, count: items.length, intensity: Math.max(...items.map(i => i.intensity), 0) }));
}

function MovementRibbon({ movements, activeVoices }: { movements: { movement: string; count: number; intensity: number }[]; activeVoices: number }) {
  return (
    <div className="movementRibbon" aria-label="Workflow movements">
      <span className="movementLead"><Mic2 size={14} /> Live movements</span>
      {movements.length ? movements.map(m => (
        <span className="movementChip" key={m.movement} style={{ '--movement-intensity': `${Math.min(100, m.intensity)}%` } as React.CSSProperties}>
          {m.movement}<b>{m.count}</b>
        </span>
      )) : <span className="movementChip empty">No active movement</span>}
      <span className="movementVoices"><Waves size={13} /> {activeVoices} audible voices</span>
    </div>
  );
}

function CueLines({ cards }: { cards: Card[] }) {
  return (
    <svg className="cueLines" aria-hidden="true" viewBox="0 0 100 100" preserveAspectRatio="none">
      {cards.slice(0, 8).map((card, index) => {
        const station = stationMeta.find(item => item.column === card.column) || stationMeta[0];
        return <path key={card.id} className={`cueLine cue-${statusClass(card.status)}`} d={`M50 43 Q${(50 + station.x) / 2} ${28 + index * 2} ${station.x} ${station.y + 5}`} />;
      })}
    </svg>
  );
}

function Conductor({ active }: { active: boolean }) {
  return (
    <div className={active ? 'conductor active' : 'conductor'} aria-label="Conductor orchestrator">
      <div className="conductorPulse" />
      <div className="conductorPodium" />
      <div className="pixelPerson conductorPerson"><span className="head" /><span className="body" /><span className="legs" /></div>
      <div className="baton" />
      <div className="speechBubble">{active ? 'cue!' : 'awaiting score'}</div>
    </div>
  );
}

function Station({ station, count }: { station: typeof stationMeta[number]; count: number }) {
  return (
    <button className={`station station-${station.kind}`} style={{ left: `${station.x}%`, top: `${station.y}%` }}>
      <span className="standTop"><FileText size={15} /></span>
      <span className="stationLabel">{station.label}</span>
      <span className="stationCount">{count}</span>
    </button>
  );
}

function EmptyHouse() {
  return (
    <div className="emptyHouse">
      <Sparkles size={22} />
      <b>No active score</b>
      <span>Create/move Linear issues into active states, then cue a poll.</span>
    </div>
  );
}

function PerformerCard({
  card,
  station,
  index,
  selected,
  busy,
  onSelect,
  onDebug,
  onMove,
  onRetry,
  onArchive
}: {
  card: Card;
  station: typeof stationMeta[number];
  index: number;
  selected: boolean;
  busy: boolean;
  onSelect: () => void;
  onDebug: () => void;
  onMove: () => void;
  onRetry: () => void;
  onArchive: () => void;
}) {
  const offsetX = ((index % 3) - 1) * 7;
  const offsetY = Math.floor(index % 6 / 3) * 9;
  const instrument = instrumentFor(card.agent, card.status);
  const status = statusClass(card.status);
  const chair = (hashString(card.backendId) % 4) + 1;

  return (
    <article
      className={`performer performer-${status} ${selected ? 'selected' : ''}`}
      style={{ left: `${station.x + offsetX}%`, top: `${station.y + offsetY + 8}%` }}
      onClick={onSelect}
    >
      <div className="performerShadow" />
      <div className={`pixelPerson musician ${status} section-${card.section.toLowerCase()}`}><span className="head" /><span className="body" /><span className="legs" /><span className="instrument">{instrument}</span></div>
      <div className="musicNote">♪</div>
      <div className="openScore"><span /> <span /> <b>{card.movement.replace(' · ', ' ')}</b></div>
      <div className="taskSlip">
        <span className="ticket">{card.identifier}</span>
        <b>{card.title}</b>
        <small>{card.instrumentName} · {card.section} · chair {chair}</small>
        <small>{card.agent} · {card.turns} turns · {card.tokens.toLocaleString()} notes</small>
        <div className="tokenBar" aria-label="Token usage"><i style={{ width: `${card.intensity}%` }} /></div>
        <div className="cardActions" onClick={event => event.stopPropagation()}>
          <button className="miniButton" onClick={onDebug} disabled={busy}><Bug size={12} />Debug</button>
          <button className="miniButton" onClick={onMove} disabled={busy}><MoveRight size={12} />Done</button>
          <button className="miniButton" onClick={onRetry} disabled={busy}><RefreshCw size={12} />Retry</button>
          <button className="miniButton" onClick={onArchive} disabled={busy}><Archive size={12} />Archive</button>
        </div>
      </div>
    </article>
  );
}

function IdleMusicianCard({ musician, index }: { musician: IdleMusician; index: number }) {
  const station = stationMeta[0];
  const offsetX = ((index % 4) - 1.5) * 6;
  const offsetY = Math.floor(index / 4) * 8;
  return (
    <article className={`performer idlePerformer ${musician.status === 'disabled' ? 'disabled' : ''}`} style={{ left: `${station.x + offsetX}%`, top: `${station.y + offsetY + 17}%` }}>
      <div className="performerShadow" />
      <div className={`pixelPerson musician idle section-${musician.section.toLowerCase()}`}><span className="head" /><span className="body" /><span className="legs" /><span className="instrument">{instrumentFor(musician.agent, musician.status)}</span></div>
      <div className="taskSlip idleSlip">
        <span className="ticket">{musician.status.toUpperCase()}</span>
        <b>{musician.agent}</b>
        <small>{musician.instrumentName} · {musician.section}</small>
        <small>{musician.role} · waiting for assignment</small>
      </div>
    </article>
  );
}

function FloatingNotes({ cards }: { cards: Card[] }) {
  return <>{cards.slice(0, 10).map((card, i) => <span key={`${card.id}-note`} className={`floatingNote n${i % 5}`}>♪</span>)}</>;
}

function ScoreConsole({
  selectedCard,
  debugPayload,
  busy,
  onDebug,
  onMove,
  onAction
}: {
  selectedCard?: Card;
  debugPayload: string | null;
  busy: boolean;
  onDebug: (id: string) => void;
  onMove: (id: string, target: string) => void;
  onAction: (id: string, action: string) => void;
}) {
  const [scoreTab, setScoreTab] = useState<'score' | 'events' | 'tools'>('score');
  return (
    <aside className="scoreConsole pixelPanel">
      <div className="consoleTabs">
        {(['score', 'events', 'tools'] as const).map(tab => (
          <button key={tab} className={scoreTab === tab ? 'scoreTabButton active' : 'scoreTabButton'} onClick={() => setScoreTab(tab)}>{tab.toUpperCase()}</button>
        ))}
      </div>
      {selectedCard ? (
        <div className="selectedScore">
          <p className="eyebrow">{selectedCard.movement}</p>
          <h2>{selectedCard.identifier}</h2>
          <h3>{selectedCard.title}</h3>
          <StatusPill status={selectedCard.status} />
          {scoreTab === 'score' && <MovementPanel card={selectedCard} />}
          {scoreTab === 'events' && <MovementEvents card={selectedCard} debugPayload={debugPayload} />}
          {scoreTab === 'tools' && <MovementTools card={selectedCard} busy={busy} onDebug={onDebug} onMove={onMove} onAction={onAction} />}
        </div>
      ) : (
        <div className="selectedScore empty"><h2>No movement selected</h2><p>The orchestra is waiting for real Linear work.</p></div>
      )}
      {debugPayload && scoreTab !== 'events' && <pre className="debugPanel">{debugPayload}</pre>}
    </aside>
  );
}

function MovementPanel({ card }: { card: Card }) {
  return (
    <>
      <div className="scoreSheet">
        <div className="staffLines"><i /><i /><i /><i /><i /></div>
        <div className="scoreNotes" style={{ '--movement-intensity': `${card.intensity}%` } as React.CSSProperties}>♪ ♫ ♩ ♬</div>
      </div>
      <dl className="definitionList compact">
        <div><dt>Section</dt><dd>{card.section}</dd></div>
        <div><dt>Instrument</dt><dd>{card.instrumentName}</dd></div>
        <div><dt>Agent</dt><dd>{card.agent}</dd></div>
        <div><dt>Backend ID</dt><dd><code>{card.backendId}</code></dd></div>
      </dl>
      <p>{card.message || card.retry || 'Waiting for the next orchestration cue.'}</p>
    </>
  );
}

function MovementEvents({ card, debugPayload }: { card: Card; debugPayload: string | null }) {
  const events = [
    ['Movement', card.movement],
    ['Status', card.status],
    ['Turns', String(card.turns)],
    ['Notes', card.tokens.toLocaleString()],
    ['Retry due', card.retry || 'none'],
    ['Last message', card.message || 'none reported']
  ];
  return (
    <div className="movementTimeline">
      {events.map(([label, value]) => <div className="timelineRow" key={label}><b>{label}</b><span>{value}</span></div>)}
      {debugPayload && <pre className="debugPanel inline">{debugPayload}</pre>}
    </div>
  );
}

function MovementTools({ card, busy, onDebug, onMove, onAction }: { card: Card; busy: boolean; onDebug: (id: string) => void; onMove: (id: string, target: string) => void; onAction: (id: string, action: string) => void }) {
  return (
    <div className="movementTools">
      <button className="button secondary" disabled={busy} onClick={() => onDebug(card.backendId)}><Bug size={14} />Open debug score</button>
      <button className="button secondary" disabled={busy} onClick={() => onMove(card.backendId, 'Done')}><MoveRight size={14} />Cue finale / Done</button>
      <button className="button secondary" disabled={busy} onClick={() => onAction(card.backendId, 'retry')}><RefreshCw size={14} />Repeat movement</button>
      <button className="button secondary" disabled={busy} onClick={() => onAction(card.backendId, 'archive')}><Archive size={14} />Archive score</button>
    </div>
  );
}


function instrumentFor(agent: string, status: string) {
  const s = `${agent} ${status}`.toLowerCase();
  if (s.includes('backoff') || s.includes('retry')) return '🥁';
  if (s.includes('review')) return '🎹';
  if (s.includes('guardian') || s.includes('block')) return '📯';
  if (s.includes('finish') || s.includes('done')) return '🎺';
  if (s.includes('builder') || s.includes('run')) return '🎻';
  return '🎼';
}

function StatusPill({ status }: { status: string }) {
  const Icon = status.includes('block') ? AlertTriangle : status.includes('done') ? CheckCircle2 : status.includes('retry') ? Clock : status.includes('execut') || status.includes('run') ? PlayCircle : CircleDot;
  return <span className={`pill ${statusClass(status)}`}><Icon size={13} />{status}</span>;
}

function statusClass(status: string) {
  const s = status.toLowerCase();
  if (s.includes('block') || s.includes('fail') || s.includes('error')) return 'danger';
  if (s.includes('retry')) return 'warning';
  if (s.includes('done') || s.includes('complete')) return 'success';
  if (s.includes('execut') || s.includes('run') || s.includes('ready')) return 'active';
  if (s.includes('review')) return 'review';
  return 'neutral';
}

function InspectorRail({
  cards,
  selectedCard,
  debugPayload,
  busy,
  onSelect,
  onDebug,
  onMove,
  onAction
}: {
  cards: Card[];
  selectedCard?: Card;
  debugPayload: string | null;
  busy: boolean;
  onSelect: (id: string) => void;
  onDebug: (id: string) => void;
  onMove: (id: string, target: string) => void;
  onAction: (id: string, action: string) => void;
}) {
  const agents = Array.from(new Map(cards.map(c => [c.agent, c])).values());
  return (
    <aside className="inspectorRail pixelPanel">
      <div className="railHeader"><h2><Users size={18} /> Section Roster</h2><span>{agents.length}</span></div>
      <div className="agentCards">
        {agents.map(agent => (
          <button className="agentTileSmall" key={agent.agent} onClick={() => onSelect(agent.id)}>
            <PixelPortrait role={statusClass(agent.status)} label={agent.agent.slice(0, 2).toUpperCase()} />
            <b>{agent.agent}</b>
            <span>{agent.identifier}</span>
            <small>{agent.status}</small>
          </button>
        ))}
        {agents.length === 0 && <p className="subtle">No active players yet.</p>}
      </div>
      <div className="railActions">
        <h3>Conductor controls</h3>
        <button className="button secondary" disabled={!selectedCard || busy} onClick={() => selectedCard && onDebug(selectedCard.backendId)}><Bug size={14} />Debug selected</button>
        <button className="button secondary" disabled={!selectedCard || busy} onClick={() => selectedCard && onMove(selectedCard.backendId, 'Done')}><MoveRight size={14} />Cue finale</button>
        <button className="button secondary" disabled={!selectedCard || busy} onClick={() => selectedCard && onAction(selectedCard.backendId, 'retry')}><RefreshCw size={14} />Repeat measure</button>
      </div>
      {debugPayload && <div className="railHint">Debug score loaded in console.</div>}
    </aside>
  );
}

function PixelPortrait({ role, label }: { role: string; label: string }) {
  return <div className={`pixelPortrait ${role}`}><span>{label}</span></div>;
}

function Agents({
  cards,
  profiles,
  idleMusicians,
  loading,
  busy,
  setSelectedCardId,
  onSaveProfile,
  onDeleteProfile
}: {
  cards: Card[];
  profiles: AgentProfile[];
  idleMusicians: IdleMusician[];
  loading: boolean;
  busy: boolean;
  setSelectedCardId: (id: string) => void;
  onSaveProfile: (profile: AgentProfile) => void;
  onDeleteProfile: (id: string) => void;
}) {
  const liveAgents = Array.from(new Map(cards.map(c => [c.agent, c])).values());
  const [editing, setEditing] = useState<AgentProfile | null>(null);
  return (
    <section className="agentsPage">
      <div className="agentsRoster pixelPanel">
        <div className="panelHeader">
          <div>
            <p className="eyebrow">Configured profiles</p>
            <h2>Agent Musicians</h2>
          </div>
          <button className="button primary" onClick={() => setEditing(emptyAgentProfile())}><Bot size={15} />New Agent</button>
        </div>
        {loading && <p className="subtle">Loading agent profiles…</p>}
        <div className="agentTileGrid">
          {liveAgents.map(a => (
            <button className="agentTile pixelPanel live" key={a.agent} onClick={() => setSelectedCardId(a.id)}>
              <PixelPortrait role={statusClass(a.status)} label={a.agent.slice(0, 2).toUpperCase()} />
              <h2>{a.agent}</h2>
              <p>Performing {a.identifier}</p>
              <b>{a.turns} turns · {a.tokens.toLocaleString()} notes</b>
              <StatusPill status={a.status} />
            </button>
          ))}
          {idleMusicians.map(m => (
            <button className={`agentTile pixelPanel idle ${m.status}`} key={m.id} onClick={() => setEditing(m.profile)}>
              <PixelPortrait role={m.status} label={m.agent.slice(0, 2).toUpperCase()} />
              <h2>{m.agent}</h2>
              <p>{m.role}</p>
              <b>{m.instrumentName} · {m.section}</b>
              <span className={`pill ${m.status}`}><Clock size={13} />{m.status}</span>
            </button>
          ))}
          {profiles.length === 0 && liveAgents.length === 0 && !loading && <div className="doc pixelPanel"><h2>No agent profiles configured</h2><p>Create an agent profile to add an idle musician to the orchestra.</p></div>}
        </div>
      </div>
      <AgentProfileForm profile={editing} busy={busy} onCancel={() => setEditing(null)} onSave={profile => { onSaveProfile(profile); setEditing(null); }} onDelete={id => { onDeleteProfile(id); setEditing(null); }} />
    </section>
  );
}

function AgentProfileForm({ profile, busy, onSave, onCancel, onDelete }: { profile: AgentProfile | null; busy: boolean; onSave: (profile: AgentProfile) => void; onCancel: () => void; onDelete: (id: string) => void }) {
  const [draft, setDraft] = useState<AgentProfile>(profile || emptyAgentProfile());
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setDraft(profile || emptyAgentProfile()); setError(null); }, [profile]);
  const update = <K extends keyof AgentProfile>(key: K, value: AgentProfile[K]) => setDraft(prev => ({ ...prev, [key]: value }));
  const submit = () => {
    try {
      const payload = AgentProfileSchema.parse({ ...draft, capabilities: String(draft.capabilities || '').split(',').map(v => v.trim()).filter(Boolean) });
      if (!payload.name.trim()) throw new Error('Name is required');
      onSave(payload);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };
  if (!profile) return <aside className="agentFormPanel pixelPanel empty"><h2><Bot size={20} /> Agent profile</h2><p className="subtle">Choose an idle musician to edit or create a new agent profile.</p></aside>;
  return (
    <aside className="agentFormPanel pixelPanel">
      <div className="panelHeader"><div><p className="eyebrow">Create / edit</p><h2><Bot size={20} /> Agent profile</h2></div></div>
      <label>Name</label><input value={draft.name} onChange={e => update('name', e.target.value)} placeholder="Violin Builder" />
      <label>Role</label><input value={draft.role} onChange={e => update('role', e.target.value)} placeholder="developer, reviewer, security" />
      <label>Profile key</label><input value={draft.profile_key} onChange={e => update('profile_key', e.target.value)} placeholder="developer" />
      <label>Section</label><select value={draft.section} onChange={e => update('section', e.target.value)}>{['Strings','Woodwinds','Brass','Percussion','Piano','Bells'].map(section => <option key={section}>{section}</option>)}</select>
      <label>Instrument</label><input value={draft.instrument_name} onChange={e => update('instrument_name', e.target.value)} placeholder="Violin" />
      <label>Max concurrent tasks</label><input type="number" min="1" value={draft.max_concurrent_tasks} onChange={e => update('max_concurrent_tasks', Number(e.target.value || 1))} />
      <label>Model</label><input value={draft.model} onChange={e => update('model', e.target.value)} placeholder="optional" />
      <label>Workspace key</label><input value={draft.workspace_key} onChange={e => update('workspace_key', e.target.value)} placeholder="agent-builder" />
      <label>Capabilities comma separated</label><input value={(draft.capabilities || []).join(', ')} onChange={e => update('capabilities', e.target.value.split(',').map(v => v.trim()).filter(Boolean))} placeholder="frontend, tests, review" />
      <label>Description</label><textarea value={draft.description} onChange={e => update('description', e.target.value)} />
      <label>Instructions</label><textarea className="tall" value={draft.instructions} onChange={e => update('instructions', e.target.value)} />
      <label className="checkRow"><input type="checkbox" checked={draft.enabled} onChange={e => update('enabled', e.target.checked)} /> Enabled / visible as idle musician</label>
      {error && <p className="formError">{error}</p>}
      <div className="formActions"><button className="button primary" disabled={busy} onClick={submit}>Save profile</button><button className="button secondary" disabled={busy} onClick={onCancel}>Cancel</button>{draft.id && <button className="button danger" disabled={busy} onClick={() => onDelete(draft.id)}>Delete</button>}</div>
    </aside>
  );
}

function WorkflowPanel({ base, state, cards }: { base: string; state?: SymphonyState; cards: Card[] }) {
  const templatesQuery = useWorkflowTemplates(base);
  const filesQuery = useWorkflowFiles(base);
  const [templateId, setTemplateId] = useState('linear_codex_judge_refiner');
  const [targetPath, setTargetPath] = useState('generated-workflow/WORKFLOW.md');
  const [overwrite, setOverwrite] = useState(false);
  const [name, setName] = useState('symphony-orchestra-workflow');
  const [objective, setObjective] = useState('Coordinate real work through generator, builder, judge, and refiner phases.');
  const [draft, setDraft] = useState('');
  const [validation, setValidation] = useState<WorkflowValidation | null>(null);
  const [preview, setPreview] = useState<WorkflowPreview | null>(null);
  const [operationLog, setOperationLog] = useState<string[]>([]);
  const [workflowError, setWorkflowError] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const selectedTemplate = templatesQuery.data?.find(t => t.id === templateId) || templatesQuery.data?.[0];
  const log = (message: string) => setOperationLog(prev => [message, ...prev].slice(0, 8));
  const fail = (label: string, err: unknown) => {
    const message = `${label}: ${err instanceof Error ? err.message : String(err)}`;
    setWorkflowError(message);
    log(message);
  };

  const generate = useMutation({
    mutationFn: async () => WorkflowGenerateSchema.parse(await api(base, '/api/workflows/generate', {
      method: 'POST',
      body: JSON.stringify({ template_id: templateId, overrides: { name, objective, max_concurrent_agents: '2', poll_interval_ms: '30000' } })
    }, 8000)),
    onSuccess: data => {
      setWorkflowError(null);
      setDraft(data.content);
      setValidation(data.validation || null);
      setPreview(null);
      log(`Generated ${data.filename || 'WORKFLOW.md'} from ${data.template_id || templateId}`);
    },
    onError: err => fail('Generate failed', err)
  });

  const validateDraft = useMutation({
    mutationFn: async () => WorkflowValidationSchema.parse(await api(base, '/api/workflows/validate', { method: 'POST', body: JSON.stringify({ content: draft }) }, 8000)),
    onSuccess: data => { setWorkflowError(null); setValidation(data); log(data.valid ? 'Judge passed: workflow is activation-ready.' : data.writable ? 'Draft is writable; activation has unresolved dispatch issues.' : 'Judge blocked: structural issues must be fixed.'); },
    onError: err => fail('Judge failed', err)
  });

  const previewDraft = useMutation({
    mutationFn: async () => WorkflowPreviewSchema.parse(await api(base, '/api/workflows/preview', { method: 'POST', body: JSON.stringify({ content: draft }) }, 8000)),
    onSuccess: data => { setWorkflowError(null); setPreview(data); setValidation(data.validation); log('Preview rendered and redacted.'); },
    onError: err => fail('Preview failed', err)
  });

  const writeDraft = useMutation({
    mutationFn: async () => api<Record<string, unknown>>(base, '/api/workflows', { method: 'POST', body: JSON.stringify({ path: targetPath, content: draft, overwrite }) }, 8000),
    onSuccess: data => { setWorkflowError(null); log(`Saved ${String(data.path || targetPath)}${data.restart_required ? ' · backend restart required to activate' : ''}`); queryClient.invalidateQueries({ queryKey: ['workflowFiles', base] }); },
    onError: err => fail('Save failed', err)
  });

  const moveWorkflow = useMutation({
    mutationFn: async () => api<Record<string, unknown>>(base, '/api/workflows/move', { method: 'POST', body: JSON.stringify({ source_path: targetPath, destination_path: targetPath.replace(/WORKFLOW\.md$/, 'archived/WORKFLOW.md'), overwrite }) }, 8000),
    onSuccess: data => { setWorkflowError(null); log(`Moved workflow to ${String(data.destination_path || 'destination')}`); queryClient.invalidateQueries({ queryKey: ['workflowFiles', base] }); },
    onError: err => fail('Move failed', err)
  });

  const busy = generate.isPending || validateDraft.isPending || previewDraft.isPending || writeDraft.isPending || moveWorkflow.isPending;
  const dispatchErrors = validation?.dispatch?.errors || [];
  const review = preview?.review || (validation ? { verdict: validation.valid ? 'pass' : validation.writable ? 'needs_refinement' : 'blocked', judge: { findings: validation.errors, warnings: validation.warnings } } : null);

  return (
    <section className="workflowBuilder">
      <div className="workflowComposer pixelPanel">
        <div className="panelHeader">
          <div>
            <p className="eyebrow">Compose Score</p>
            <h2><Workflow size={20} /> WORKFLOW.md Builder</h2>
          </div>
          <span className={`pill ${validation?.valid ? 'success' : validation?.writable ? 'warning' : 'idle'}`}>{validation?.valid ? 'ready to activate' : validation?.writable ? 'writable draft' : 'draft'}</span>
        </div>

        <label className="workflowSelectLabel">Template
          <select value={templateId} onChange={e => setTemplateId(e.target.value)} disabled={busy || templatesQuery.isLoading}>
            {(templatesQuery.data || []).map(template => <option key={template.id} value={template.id}>{template.name}</option>)}
          </select>
        </label>
        {selectedTemplate && <div className="workflowSelectedTemplate pixelPanel"><b>{selectedTemplate.name}</b><small>{selectedTemplate.description}</small><span>{selectedTemplate.tags.join(' · ')}</span></div>}
        <div className="workflowTemplateGrid">
          {(templatesQuery.data || []).map(template => (
            <button key={template.id} type="button" className={`workflowTemplateCard pixelPanel ${template.id === templateId ? 'selected' : ''}`} onClick={() => setTemplateId(template.id)}>
              <b>{template.name}</b>
              <small>{template.description}</small>
              <span>{template.tags.join(' · ')}</span>
            </button>
          ))}
          {!templatesQuery.isLoading && (templatesQuery.data || []).length === 0 && <p className="subtle">No workflow templates returned by the backend.</p>}
        </div>

        <div className="workflowFieldGrid">
          <label>Workflow name<input value={name} onChange={e => setName(e.target.value)} /></label>
          <label>Target path<input value={targetPath} onChange={e => setTargetPath(e.target.value)} placeholder="WORKFLOW.md or folder/WORKFLOW.md" /></label>
        </div>
        <label>Objective<textarea value={objective} onChange={e => setObjective(e.target.value)} /></label>
        <div className="formActions">
          <button className="button primary" disabled={busy} onClick={() => generate.mutate()}><Music2 size={15} />Generate</button>
          <button className="button secondary" title={!draft ? 'Generate or paste WORKFLOW.md content first.' : 'Run backend workflow validation/judge.'} disabled={busy || !draft} onClick={() => validateDraft.mutate()}>Judge</button>
          <button className="button secondary" disabled={busy || !draft} onClick={() => previewDraft.mutate()}>Preview</button>
        </div>
        <textarea className="workflowEditor" value={draft} onChange={e => { setDraft(e.target.value); setValidation(null); setPreview(null); }} placeholder="Generate or paste WORKFLOW.md content here. Missing facts should stay unresolved, not invented." />
      </div>

      <aside className="workflowInspector pixelPanel">
        <div className="panelHeader"><div><p className="eyebrow">Rehearsal Desk</p><h2>Judge / Refiner / Location</h2></div></div>
        <div className="targetPreview">
          <b>Backend-managed root</b>
          <code>{filesQuery.data?.root || 'loading…'}</code>
          <small>Tauri stays an HTTP client; file writes are backend-mediated and path-safe.</small>
        </div>
        <label className="checkRow"><input type="checkbox" checked={overwrite} onChange={e => setOverwrite(e.target.checked)} /> Allow overwrite after explicit confirmation</label>
        <div className="formActions">
          <button className="button primary" disabled={busy || !draft} onClick={() => writeDraft.mutate()}>Save WORKFLOW.md</button>
          <button className="button secondary" disabled={busy} onClick={() => filesQuery.refetch()}>Refresh list</button>
          <button className="button danger" disabled={busy || !targetPath} onClick={() => moveWorkflow.mutate()}>Move to archive</button>
        </div>

        {workflowError && <p className="formError">{workflowError}</p>}
        <div className="resultPanel">
          <h3>Validation</h3>
          {validation ? <>
            <p><b>{validation.valid ? 'Pass' : validation.writable ? 'Writable with unresolved activation checks' : 'Blocked'}</b></p>
            {validation.errors.length > 0 && <ul>{validation.errors.map(e => <li key={e}>{e}</li>)}</ul>}
            {dispatchErrors.length > 0 && <ul>{dispatchErrors.map(e => <li key={e}>Activation: {e}</li>)}</ul>}
            {validation.warnings.length > 0 && <ul>{validation.warnings.map(w => <li key={w}>Warning: {w}</li>)}</ul>}
          </> : <p className="subtle">Generate or judge a draft to see validation.</p>}
        </div>

        <div className="resultPanel">
          <h3>Judge / Refiner</h3>
          {review ? <pre>{JSON.stringify(review, null, 2)}</pre> : <p className="subtle">No review yet.</p>}
        </div>

        <div className="resultPanel">
          <h3>Managed workflows</h3>
          {(filesQuery.data?.workflows || []).map((wf: any) => <div className="workflowRow" key={wf.path}><b>{wf.path}</b><span>{wf.active ? 'active' : wf.valid ? 'valid file' : 'invalid'}</span></div>)}
          {(filesQuery.data?.workflows || []).length === 0 && <p className="subtle">No managed WORKFLOW.md files discovered.</p>}
        </div>

        <div className="operationLog">
          <h3>Operation log</h3>
          {operationLog.map((line, i) => <p key={`${line}-${i}`}>{line}</p>)}
          {operationLog.length === 0 && <p className="subtle">No workflow operations yet.</p>}
        </div>
      </aside>
    </section>
  );
}

function SafetyPanel() {
  return (
    <section className="doc pixelPanel">
      <h2><ShieldAlert size={20} /> Safety Posture</h2>
      <ul className="checkList">
        <li>Agent working directories are constrained to per-issue workspaces.</li>
        <li>Workspace keys allow only alphanumeric, dot, underscore, and dash characters.</li>
        <li>Secrets use environment indirection and are not emitted in public config JSON.</li>
        <li>Hooks time out to prevent orchestration stalls.</li>
      </ul>
    </section>
  );
}

function SettingsPanel({
  base,
  saveBase,
  codexAuth,
  codexLoading,
  codexError,
  codexBusy,
  backendRuntime,
  backendRuntimeError,
  backendBusy,
  backendLogs,
  onStartBackend,
  onRestartBackend,
  onRefreshBackend,
  onLoadBackendLogs,
  onStartCodexLogin,
  onCheckCodex,
  onLogoutCodex
}: {
  base: string;
  saveBase: (v: string) => void;
  codexAuth?: CodexAuthPayload;
  codexLoading: boolean;
  codexError?: string;
  codexBusy: boolean;
  backendRuntime?: BackendRuntimePayload;
  backendRuntimeError?: string;
  backendBusy: boolean;
  backendLogs?: { logPath?: string; text: string };
  onStartBackend: () => void;
  onRestartBackend: () => void;
  onRefreshBackend: () => void;
  onLoadBackendLogs: () => void;
  onStartCodexLogin: () => void;
  onCheckCodex: () => void;
  onLogoutCodex: () => void;
}) {
  const [v, setV] = useState(base);
  useEffect(() => setV(base), [base]);
  const codexConnected = Boolean(codexAuth?.authenticated || codexAuth?.status === 'authenticated' || codexAuth?.status === 'connected');
  const codexAvailable = codexAuth?.available !== false;
  const codexStatus = codexLoading
    ? 'checking…'
    : codexError
      ? 'backend unavailable'
      : codexConnected
        ? 'Codex Pro connected'
        : codexAvailable
          ? 'sign-in needed'
          : 'Codex CLI missing';
  return (
    <section className="settingsStack">
      <div className="doc pixelPanel settingsHero">
        <div>
          <p className="eyebrow">Runtime connection</p>
          <h2><Settings size={20} /> Settings</h2>
          <p className="subtle">Packaged desktop builds talk to the local Symphony backend at <code>127.0.0.1:4004</code>. Dev builds can leave this blank for the Vite proxy.</p>
        </div>
        <span className={`pill ${codexConnected ? 'active' : 'neutral'}`}><BrainCircuit size={14} /> {codexStatus}</span>
      </div>

      <div className="doc pixelPanel backendControlPanel">
        <div className="panelHeader">
          <div>
            <p className="eyebrow">Managed local runtime</p>
            <h2><Server size={20} /> Bundled Symphony backend</h2>
          </div>
          <span className={`pill ${backendRuntime?.healthy ? 'active' : 'neutral'}`}>{backendRuntime?.healthy ? 'Backend ready' : backendBusy ? 'Starting…' : 'Backend manager'}</span>
        </div>
        <p className="subtle">The packaged desktop app now starts and supervises its own local backend. No separate backend service should be required.</p>
        <div className="codexStatusGrid">
          <div><span>Managed</span><b>{backendRuntime?.managed ? 'yes' : 'not yet'}</b></div>
          <div><span>Healthy</span><b>{backendRuntime?.healthy ? 'yes' : 'pending'}</b></div>
          <div><span>Port</span><b>{backendRuntime?.port || 'auto'}</b></div>
          <div><span>Source</span><b>{String(backendRuntime?.source || 'bundled backend')}</b></div>
        </div>
        {backendRuntimeError && <p className="formError">{backendRuntimeError}</p>}
        {backendRuntime?.lastError && <p className="formError">{String(backendRuntime.lastError)}</p>}
        <div className="formActions">
          <button className="button primary" disabled={backendBusy} onClick={onStartBackend}><PlayCircle size={15} /> Start bundled backend</button>
          <button className="button secondary" disabled={backendBusy} onClick={onRestartBackend}><RefreshCw size={15} /> Restart backend</button>
          <button className="button secondary" disabled={backendBusy} onClick={onRefreshBackend}>Refresh status</button>
          <button className="button secondary" disabled={backendBusy} onClick={onLoadBackendLogs}>Show logs</button>
        </div>
        <div className="targetPreview">
          <b>Current API base</b>
          <code>{backendRuntime?.baseUrl || base || 'starting bundled backend…'}</code>
          {backendRuntime?.logPath && <small>Backend log: {backendRuntime.logPath}</small>}
        </div>
        {backendLogs?.text && <pre className="backendLogBox">{backendLogs.text}</pre>}
        <details className="advancedBackendSettings">
          <summary>Advanced: override API base URL</summary>
          <label htmlFor="apiBase">Symphony API base URL</label>
          <div className="settingsRow">
            <input id="apiBase" value={v} onChange={e => setV(e.target.value)} placeholder="Leave blank to use bundled backend" />
            <button className="button primary" onClick={() => saveBase(v)}>Save override</button>
            <button className="button secondary" onClick={() => { localStorage.removeItem('symphony.apiBase'); setV(''); onStartBackend(); }}>Use bundled backend</button>
          </div>
        </details>
      </div>

      <div className="doc pixelPanel codexConnectPanel">
        <div className="panelHeader">
          <div>
            <p className="eyebrow">Agent spawning</p>
            <h2><BrainCircuit size={20} /> Connect ChatGPT Codex Pro</h2>
          </div>
          <span className={`pill ${codexConnected ? 'active' : codexAvailable ? 'neutral' : 'danger'}`}>{codexStatus}</span>
        </div>
        <p className="subtle">Symphony uses the local Codex CLI OAuth/session. Tokens stay owned by the Codex CLI; Symphony only checks sanitized status and asks the CLI to start login/logout.</p>
        <div className="codexStatusGrid">
          <div><span>CLI available</span><b>{codexAvailable ? 'yes' : 'no'}</b></div>
          <div><span>Authenticated</span><b>{codexConnected ? 'yes' : 'no'}</b></div>
          <div><span>Version</span><b>{String(codexAuth?.version || 'unknown')}</b></div>
          <div><span>Command</span><b>{String(codexAuth?.command || 'codex')}</b></div>
        </div>
        {codexError && <p className="formError">{codexError}</p>}
        {codexAuth?.message && <p className="subtle">{String(codexAuth.message)}</p>}
        {codexAuth?.login_command && <div className="targetPreview"><b>If a browser did not open, run:</b><code>{String(codexAuth.login_command)}</code></div>}
        <div className="formActions">
          <button className="button primary" disabled={codexBusy} onClick={onStartCodexLogin}><BrainCircuit size={15} /> Connect Codex Pro</button>
          <button className="button secondary" disabled={codexBusy} onClick={onCheckCodex}><RefreshCw size={15} /> Check connection</button>
          <button className="button danger" disabled={codexBusy} onClick={onLogoutCodex}>Disconnect</button>
        </div>
        <p className="subtle">After connecting, create Agent profiles and Symphony will launch real Codex-backed workers using your local Codex Pro session.</p>
      </div>
    </section>
  );
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </React.StrictMode>
);
