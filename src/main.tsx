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
  stage: z.string().optional(),
  phase: z.string().optional(),
  operator_status: z.string().optional(),
  operator_summary: z.string().nullable().optional(),
  workspace_path: z.string().nullable().optional(),
  session_id: z.string().nullable().optional(),
  last_event: z.string().nullable().optional(),
  last_message: z.string().nullable().optional(),
  turn_count: z.number().optional(),
  tokens: z.object({ total_tokens: z.number().default(0) }).passthrough().optional(),
  agent_profile: z.any().optional(),
  agent_profile_id: z.string().nullable().optional(),
  agent_name: z.string().nullable().optional(),
  agent_role: z.string().nullable().optional(),
  agent_section: z.string().nullable().optional(),
  instrument_name: z.string().nullable().optional(),
  agent_profile_status: z.string().nullable().optional(),
  judge_verdict: z.any().optional(),
  verdict: z.string().nullable().optional(),
  verdict_path: z.string().nullable().optional(),
  refiner_attempt: z.number().nullable().optional(),
  refiner_max_attempts: z.number().nullable().optional(),
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
  music: z.any().optional(),
  stage_position: z.any().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional()
}).passthrough();
const AgentStorageSchema = z.object({ path: z.string().optional(), count: z.number().optional(), exists: z.boolean().optional(), writable: z.boolean().optional() }).passthrough();
const AgentProfilesResponseSchema = z.object({ profiles: z.array(AgentProfileSchema).default([]), storage: AgentStorageSchema.optional(), count: z.number().optional() });
type AgentProfile = z.infer<typeof AgentProfileSchema>;
type AgentProfilesResponse = z.infer<typeof AgentProfilesResponseSchema>;
type StagePosition = {
  section?: string;
  seat?: string;
  x?: number;
  y?: number;
};
type MusicProfile = {
  motif?: string;
  dynamic?: string;
  register?: string;
};
type IdleMusician = {
  id: string;
  profile: AgentProfile;
  agent: string;
  role: string;
  section: string;
  instrumentName: string;
  music?: MusicProfile;
  stagePosition?: StagePosition;
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
  provenance: z.any().optional(),
  agent_profiles: z.array(AgentProfileSchema).default([]),
  agent_profile_changes: z.object({
    created: z.array(z.string()).default([]),
    updated: z.array(z.string()).default([]),
    count: z.number().default(0)
  }).optional()
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
type Tab = 'console' | 'agents' | 'workflow' | 'ledger' | 'safety' | 'settings';
type ApiMode = 'initializing' | 'desktop' | 'proxy' | 'override' | 'desktop-error';
type Card = {
  id: string;
  backendId: string;
  identifier: string;
  title: string;
  column: string;
  status: string;
  agent: string;
  agentProfileId?: string;
  agentRole?: string;
  agentProfileStatus?: string;
  phase?: string;
  stage?: string;
  turns: number;
  tokens: number;
  priority?: number;
  message?: string;
  retry?: string;
  movement: string;
  instrumentName: string;
  section: string;
  music?: MusicProfile;
  stagePosition?: StagePosition;
  intensity: number;
  source: 'live';
  raw?: unknown;
};

const columns = ['Ready', 'In Progress', 'Human Review', 'Retry', 'Blocked', 'Done'];
const orchestraSections = ['Strings', 'Woodwinds', 'Brass', 'Percussion', 'Piano', 'Bells'];
const stageSeats = [
  'front-left',
  'front-center',
  'front-right',
  'mid-left',
  'mid-center',
  'mid-right',
  'back-left',
  'back-center',
  'back-right'
];
const musicDynamics = ['piano', 'mezzo-piano', 'mezzo-forte', 'forte'];
const musicRegisters = ['low', 'lower-middle', 'middle', 'upper-middle', 'high'];
const nav: { id: Tab; label: string; icon: React.ElementType }[] = [
  { id: 'console', label: 'Console', icon: Command },
  { id: 'agents', label: 'Agents', icon: Bot },
  { id: 'workflow', label: 'Workflow', icon: GitBranch },
  { id: 'ledger', label: 'Ledger', icon: Activity },
  { id: 'safety', label: 'Safety', icon: ShieldAlert },
  { id: 'settings', label: 'Settings', icon: Settings }
];

function getApiBase() {
  const saved = localStorage.getItem('symphony.apiBase');
  return saved?.trim() || '';
}

function hasTauriBridge() {
  const win = window as unknown as { __TAURI_INTERNALS__?: unknown; __TAURI__?: unknown };
  return Boolean(win.__TAURI_INTERNALS__ || win.__TAURI__);
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

function useSymphonyState(base: string, enabled = true) {
  return useQuery({
    queryKey: ['state', base],
    queryFn: async () => StateSchema.parse(await api(base, '/api/v1/state')),
    refetchInterval: 7_500,
    enabled
  });
}

function useKanban(base: string, enabled = true) {
  return useQuery({
    queryKey: ['kanban', base],
    queryFn: async () => KanbanSchema.parse(await api(base, '/api/kanban')),
    refetchInterval: 7_500,
    enabled
  });
}

function useAgentProfiles(base: string, enabled = true) {
  return useQuery<AgentProfilesResponse>({
    queryKey: ['agentProfiles', base],
    queryFn: async () => AgentProfilesResponseSchema.parse(await api(base, '/api/agents')),
    refetchInterval: 15_000,
    enabled
  });
}

function useWorkflowTemplates(base: string, enabled = true) {
  return useQuery({
    queryKey: ['workflowTemplates', base],
    queryFn: async () => WorkflowTemplatesSchema.parse(await api(base, '/api/workflows/templates')).templates,
    refetchInterval: false,
    staleTime: 60_000,
    enabled
  });
}

function useWorkflowFiles(base: string, enabled = true) {
  return useQuery({
    queryKey: ['workflowFiles', base],
    queryFn: async () => WorkflowListSchema.parse(await api(base, '/api/workflows')),
    refetchInterval: false,
    staleTime: 30_000,
    enabled
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
    current_assignments: [],
    music: { motif: 'Solo entrance', dynamic: 'mezzo-piano', register: 'middle' },
    stage_position: { section: 'strings', seat: 'front-center' }
  });
}

function makeIdleMusicians(profiles: AgentProfile[], liveCards: Card[]): IdleMusician[] {
  const activeProfileIds = new Set(liveCards.map(card => card.agentProfileId).filter(Boolean));
  const activeNames = new Set(liveCards.map(card => card.agent.toLowerCase()));
  return profiles
    .filter(profile => !activeProfileIds.has(profile.id) && !activeNames.has(profile.name.toLowerCase()))
    .map(profile => ({
      id: `profile-${profile.id}`,
      profile,
      agent: profile.name,
      role: profile.role,
      section: profile.section,
      instrumentName: profile.instrument_name,
      music: musicProfile(profile.music),
      stagePosition: stagePosition(profile.stage_position),
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
  if (s.includes('refin')) return 'Refiner';
  if (column === 'Human Review' || s.includes('review') || s.includes('judge')) return 'Reviewer';
  if (column === 'In Progress' || s.includes('run') || s.includes('execut')) return 'Builder';
  return 'Planner';
}

function movementFor(column: string, status: string) {
  const s = `${column} ${status}`.toLowerCase();
  if (s.includes('block')) return 'Movement V · Dissonance';
  if (s.includes('retry')) return 'Movement IV · Rehearsal';
  if (s.includes('refin')) return 'Movement III · Refinement';
  if (s.includes('review') || s.includes('judge')) return 'Movement III · Review Cadenza';
  if (s.includes('done') || s.includes('complete')) return 'Finale · Resolution';
  if (s.includes('progress') || s.includes('run') || s.includes('execut')) return 'Movement II · Implementation';
  return 'Movement I · Overture';
}

function sectionFor(column: string, status: string, labels?: unknown[]) {
  const text = `${column} ${status} ${(labels || []).map(String).join(' ')}`.toLowerCase();
  if (text.includes('test') || text.includes('ci')) return 'Percussion';
  if (text.includes('security') || text.includes('guard') || text.includes('block')) return 'Brass';
  if (text.includes('refin')) return 'Brass';
  if (text.includes('review') || text.includes('judge')) return 'Piano';
  if (text.includes('research') || text.includes('plan')) return 'Woodwinds';
  if (text.includes('retry')) return 'Timpani';
  if (text.includes('done') || text.includes('complete')) return 'Bells';
  return 'Strings';
}

function instrumentNameFor(section: string, agent: string, status: string) {
  const s = `${section} ${agent} ${status}`.toLowerCase();
  if (s.includes('timpani') || s.includes('retry') || s.includes('percussion')) return 'Timpani';
  if (s.includes('brass') || s.includes('guardian') || s.includes('block')) return 'French Horn';
  if (s.includes('piano') || s.includes('review') || s.includes('judge')) return 'Piano';
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

function useAgentOrchestra({ enabled, cards, idleMusicians, offline }: { enabled: boolean; cards: Card[]; idleMusicians: IdleMusician[]; offline: boolean }): OrchestraAudioState {
  const cardsRef = useRef(cards);
  const idleRef = useRef(idleMusicians);
  const offlineRef = useRef(offline);
  const ctxRef = useRef<AudioContext | null>(null);
  const masterRef = useRef<GainNode | null>(null);
  const timerRef = useRef<number | null>(null);
  const stepRef = useRef(0);
  const nextTimeRef = useRef(0);
  const [audioState, setAudioState] = useState<OrchestraAudioState>({ enabled, ready: false, activeVoices: 0 });

  useEffect(() => {
    cardsRef.current = cards;
    idleRef.current = idleMusicians;
    offlineRef.current = offline;
    const activeVoices = orchestraVoiceCount(cards, idleMusicians, offline);
    setAudioState(prev => (
      prev.enabled === enabled && prev.activeVoices === activeVoices
        ? prev
        : { ...prev, enabled, activeVoices }
    ));
  }, [cards, idleMusicians, enabled, offline]);

  useEffect(() => {
    if (!enabled) {
      if (masterRef.current && ctxRef.current) masterRef.current.gain.linearRampToValueAtTime(0.0001, ctxRef.current.currentTime + 0.25);
      if (timerRef.current) window.clearInterval(timerRef.current);
      timerRef.current = null;
      const ready = Boolean(ctxRef.current);
      setAudioState(prev => (
        !prev.enabled && prev.ready === ready && prev.activeVoices === 0
          ? prev
          : { ...prev, enabled: false, ready, activeVoices: 0 }
      ));
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
      timerRef.current = window.setInterval(() => scheduleOrchestra(ctx, masterRef.current!, cardsRef, idleRef, offlineRef, stepRef, nextTimeRef), 30);
      setAudioState({ enabled: true, ready: true, activeVoices: orchestraVoiceCount(cardsRef.current, idleRef.current, offlineRef.current) });
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

function orchestraVoiceCount(cards: Card[], idleMusicians: IdleMusician[], offline: boolean) {
  if (offline) return 0;
  const idleCount = idleMusicians.filter(musician => musician.status === 'idle').length;
  return Math.min(12, cards.length + Math.min(8, idleCount));
}

function scheduleOrchestra(
  ctx: AudioContext,
  out: AudioNode,
  cardsRef: React.MutableRefObject<Card[]>,
  idleRef: React.MutableRefObject<IdleMusician[]>,
  offlineRef: React.MutableRefObject<boolean>,
  stepRef: React.MutableRefObject<number>,
  nextTimeRef: React.MutableRefObject<number>
) {
  const stepDur = 60 / 88 / 2;
  while (nextTimeRef.current < ctx.currentTime + 0.14) {
    const cards = offlineRef.current ? [] : prioritizeCards(cardsRef.current).slice(0, 8);
    const idleMusicians = offlineRef.current ? [] : prioritizeIdleMusicians(idleRef.current).slice(0, Math.max(0, 12 - cards.length));
    const totalVoices = cards.length + idleMusicians.length;
    if (totalVoices) {
      const hasBlocked = cards.some(card => card.column === 'Blocked');
      const hasRetry = cards.some(card => card.column === 'Retry');
      const scale = hasBlocked ? audioScales.blocked : hasRetry ? audioScales.retry : cards.some(card => card.column === 'In Progress') ? audioScales.active : audioScales.calm;
      cards.forEach((card, index) => scheduleCardVoice(ctx, out, card, index, totalVoices, scale, stepRef.current, nextTimeRef.current));
      idleMusicians.forEach((musician, index) => scheduleIdleVoice(ctx, out, musician, cards.length + index, totalVoices, scale, stepRef.current, nextTimeRef.current));
    }
    stepRef.current += 1;
    nextTimeRef.current += stepDur;
  }
}

function prioritizeCards(cards: Card[]) {
  const weight = (card: Card) => ({ Blocked: 0, Retry: 1, 'In Progress': 2, 'Human Review': 3, Ready: 4, Done: 5 }[card.column] ?? 6);
  return [...cards].sort((a, b) => weight(a) - weight(b));
}

function prioritizeIdleMusicians(musicians: IdleMusician[]) {
  const sectionWeight = (section: string) => ({ Strings: 0, Woodwinds: 1, Brass: 2, Piano: 3, Percussion: 4, Bells: 5 }[section] ?? 6);
  return musicians
    .filter(musician => musician.status === 'idle')
    .sort((a, b) => sectionWeight(a.section) - sectionWeight(b.section) || a.agent.localeCompare(b.agent));
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

function scheduleIdleVoice(ctx: AudioContext, out: AudioNode, musician: IdleMusician, index: number, total: number, scale: number[], step: number, time: number) {
  const spec = synthSpec({
    column: 'Ready',
    status: musician.status,
    agent: musician.agent,
    instrumentName: musician.instrumentName,
    section: musician.section,
    music: musician.music
  });
  if (!shouldPlay(idleRhythmFor(spec.rhythm), step, index)) return;
  const seed = hashString(musician.id);
  const degree = (step + index + seed) % scale.length;
  const midi = 36 + spec.octave * 12 + scale[degree] + (index % 2 === 0 ? 0 : 7);
  const pan = total <= 1 ? 0 : -0.7 + (index / (total - 1)) * 1.4;
  playSynthNote(ctx, out, { time, freq: midiToFreq(midi), duration: spec.duration * 1.35, gain: spec.gain * 0.45, type: spec.type, filterHz: spec.filterHz, pan });
}

type SynthSpec = { type: OscillatorType; octave: number; gain: number; duration: number; filterHz: number; rhythm: string };

function synthSpec(voice: { column?: string; status: string; agent: string; instrumentName?: string; section?: string; music?: MusicProfile }) {
  const state = `${voice.column || ''} ${voice.status} ${voice.agent}`.toLowerCase();
  const instrument = `${voice.instrumentName || ''} ${voice.section || ''}`.toLowerCase();
  let spec: SynthSpec = { type: 'sine' as OscillatorType, octave: 4, gain: 0.014, duration: 0.22, filterHz: 3000, rhythm: 'sparse' };
  if (state.includes('block') || state.includes('guardian')) spec = { type: 'triangle' as OscillatorType, octave: 2, gain: 0.026, duration: 0.7, filterHz: 420, rhythm: 'drone' };
  else if (state.includes('retry') || state.includes('backoff')) spec = { type: 'sawtooth' as OscillatorType, octave: 3, gain: 0.028, duration: 0.16, filterHz: 900, rhythm: 'retry' };
  else if (instrument.includes('timpani') || instrument.includes('percussion') || instrument.includes('drum')) spec = { type: 'sawtooth' as OscillatorType, octave: 2, gain: 0.026, duration: 0.18, filterHz: 760, rhythm: 'retry' };
  else if (instrument.includes('piano')) spec = { type: 'triangle' as OscillatorType, octave: 4, gain: 0.024, duration: 0.32, filterHz: 2400, rhythm: 'review' };
  else if (instrument.includes('horn') || instrument.includes('trumpet') || instrument.includes('brass')) spec = { type: 'triangle' as OscillatorType, octave: 3, gain: 0.021, duration: 0.48, filterHz: 1150, rhythm: 'sparse' };
  else if (instrument.includes('clarinet') || instrument.includes('oboe') || instrument.includes('flute') || instrument.includes('woodwind')) spec = { type: 'triangle' as OscillatorType, octave: 4, gain: 0.017, duration: 0.3, filterHz: 2100, rhythm: 'sparse' };
  else if (instrument.includes('glockenspiel') || instrument.includes('bell')) spec = { type: 'sine' as OscillatorType, octave: 5, gain: 0.022, duration: 0.38, filterHz: 6200, rhythm: 'cadence' };
  else if (state.includes('review') || state.includes('judge')) spec = { type: 'triangle' as OscillatorType, octave: 4, gain: 0.024, duration: 0.32, filterHz: 2400, rhythm: 'review' };
  else if (state.includes('done') || state.includes('finish')) spec = { type: 'sine' as OscillatorType, octave: 5, gain: 0.024, duration: 0.42, filterHz: 6000, rhythm: 'cadence' };
  else if (state.includes('progress') || state.includes('run') || state.includes('builder') || instrument.includes('violin') || instrument.includes('viola') || instrument.includes('strings')) spec = { type: 'square' as OscillatorType, octave: 4, gain: 0.022, duration: 0.13, filterHz: 1700, rhythm: 'arpeggio' };
  return applyMusicProfile(spec, voice.music);
}

function applyMusicProfile(spec: SynthSpec, music?: MusicProfile): SynthSpec {
  if (!music) return spec;
  const dynamicGain: Record<string, number> = { piano: 0.76, 'mezzo-piano': 0.9, 'mezzo-forte': 1.08, forte: 1.22 };
  const registerShift: Record<string, number> = { low: -1, 'lower-middle': 0, middle: 0, 'upper-middle': 1, high: 1 };
  const motif = (music.motif || '').toLowerCase();
  const gain = spec.gain * (dynamicGain[music.dynamic || ''] || 1);
  const octave = Math.round(clamp(spec.octave + (registerShift[music.register || ''] || 0), 2, 6));
  let rhythm = spec.rhythm;
  if (motif.includes('drone') || motif.includes('sustain')) rhythm = 'drone';
  else if (motif.includes('pulse') || motif.includes('ostinato')) rhythm = 'arpeggio';
  else if (motif.includes('cadenza') || motif.includes('finale')) rhythm = 'cadence';
  else if (motif.includes('sparse')) rhythm = 'sparse';
  return { ...spec, gain, octave, rhythm };
}

function idleRhythmFor(rhythm: string) {
  if (rhythm === 'retry') return 'idle-pulse';
  if (rhythm === 'cadence') return 'idle-cadence';
  return 'idle';
}

function shouldPlay(rhythm: string, step: number, index: number) {
  if (rhythm === 'drone') return step % 8 === index % 4;
  if (rhythm === 'retry') return step % 3 === index % 3;
  if (rhythm === 'review') return step % 4 === index % 2;
  if (rhythm === 'cadence') return step % 8 === index % 2;
  if (rhythm === 'arpeggio') return step % 2 === index % 2;
  if (rhythm === 'idle-pulse') return step % 10 === index % 5;
  if (rhythm === 'idle-cadence') return step % 16 === index % 4;
  if (rhythm === 'idle') return step % 12 === index % 6;
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
      const rawRecord = raw as Record<string, unknown>;
      const backendId = raw.issue_id || raw.id || raw.linear_identifier || raw.identifier || `${column.id}-${i}`;
      const identifier = raw.linear_identifier || raw.identifier || backendId;
      const phase = stringField(rawRecord, 'phase') || stringField(rawRecord, 'stage') || undefined;
      const status = String(raw.operator_status || phase || raw.status || raw.last_event || raw.state || column.id || 'ready');
      const normalizedColumn = normalizeColumn(column.title || column.id);

      const turns = raw.turn_count || raw.attempt || 0;
      const tokens = raw.tokens?.total_tokens || 0;
      const priority = raw.priority ?? undefined;
      const assignedProfile = agentProfileFromCard(raw);
      const agent = assignedProfile?.name || stringField(rawRecord, 'agent_name') || liveAgentFor(normalizedColumn, status);
      const section = assignedProfile?.section || stringField(rawRecord, 'agent_section') || sectionFor(normalizedColumn, status, raw.labels);
      const instrumentName = assignedProfile?.instrument_name || stringField(rawRecord, 'instrument_name') || instrumentNameFor(section, agent, status);
      const music = musicProfile(assignedProfile?.music);
      const profileStagePosition = stagePosition(assignedProfile?.stage_position);

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
        agentProfileId: assignedProfile?.id || stringField(rawRecord, 'agent_profile_id'),
        agentRole: assignedProfile?.role || stringField(rawRecord, 'agent_role'),
        agentProfileStatus: assignedProfile?.status || stringField(rawRecord, 'agent_profile_status'),
        phase,
        stage: stringField(rawRecord, 'stage') || phase,
        message: raw.operator_summary || raw.last_message || raw.error || undefined,
        retry: raw.due_at || undefined,
        movement: movementFor(normalizedColumn, status),
        instrumentName,
        section,
        music,
        stagePosition: profileStagePosition,
        intensity: intensityFor(tokens, turns, priority),
        source: 'live' as const,
        raw
      };
    })
  );
}

function agentProfileFromCard(raw: z.infer<typeof KanbanCardSchema>) {
  const profile = raw.agent_profile;
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) return null;
  const value = profile as Record<string, unknown>;
  const id = stringField(value, 'id');
  const name = stringField(value, 'name');
  if (!id && !name) return null;

  return {
    id,
    name: name || id,
    role: stringField(value, 'role') || 'Agent',
    status: stringField(value, 'status') || 'idle',
    section: stringField(value, 'section') || 'Strings',
    instrument_name: stringField(value, 'instrument_name') || stringField(value, 'instrumentName') || 'Violin',
    music: value.music,
    stage_position: value.stage_position || value.stagePosition
  };
}

function stringField(value: Record<string, unknown>, key: string) {
  const field = value[key];
  return typeof field === 'string' && field.trim() ? field : '';
}

function numberField(value: Record<string, unknown>, key: string) {
  const field = value[key];
  return typeof field === 'number' && Number.isFinite(field) ? field : undefined;
}

function musicProfile(value: unknown): MusicProfile | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const profile: MusicProfile = {};
  const motif = stringField(record, 'motif');
  const dynamic = stringField(record, 'dynamic');
  const register = stringField(record, 'register');
  if (motif) profile.motif = motif;
  if (dynamic) profile.dynamic = dynamic;
  if (register) profile.register = register;
  return Object.keys(profile).length ? profile : undefined;
}

function stagePosition(value: unknown): StagePosition | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const position: StagePosition = {};
  const section = stringField(record, 'section');
  const seat = stringField(record, 'seat');
  const x = numberField(record, 'x');
  const y = numberField(record, 'y');
  if (section) position.section = section;
  if (seat) position.seat = seat;
  if (x !== undefined) position.x = x;
  if (y !== undefined) position.y = y;
  return Object.keys(position).length ? position : undefined;
}


type CodexAuthPayload = {
  available?: boolean;
  cli_available?: boolean;
  connected?: boolean;
  authenticated?: boolean;
  state?: string;
  status?: string;
  message?: string;
  version?: string;
  cli_version?: string;
  command?: string;
  configured_command?: string;
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

const ProviderSchema = z.object({
  id: z.string(),
  name: z.string(),
  active: z.boolean().default(false),
  default: z.boolean().default(false),
  available: z.boolean().default(false),
  selectable: z.boolean().optional(),
  configured: z.boolean().optional(),
  implemented: z.boolean().optional(),
  authenticated: z.boolean().optional(),
  status: z.string().default('unknown'),
  command: z.string().nullable().optional(),
  endpoint: z.string().nullable().optional(),
  auth_source: z.string().nullable().optional(),
  blocked_reason: z.string().nullable().optional(),
  message: z.string().nullable().optional()
}).passthrough();

const ProviderStatusSchema = z.object({
  active_provider: z.string().default('direct_codex'),
  default_provider: z.string().default('direct_codex'),
  contract_version: z.number().default(1),
  provider_contract: z.array(z.string()).default(['direct_codex', 'agent_zero']),
  providers: z.array(ProviderSchema).default([]),
  status: z.string().default('unknown'),
  generated_at: z.string().optional()
}).passthrough();

type ProviderStatusPayload = z.infer<typeof ProviderStatusSchema>;
type Provider = z.infer<typeof ProviderSchema>;

type OrchestrationEvent = {
  id: string;
  sequence?: number;
  type: string;
  provider?: string;
  source?: string;
  occurred_at?: string;
  issue_id?: string;
  issue_identifier?: string;
  stage?: string;
  status?: string;
  action?: string;
  message?: string;
  data?: Record<string, unknown>;
  [key: string]: unknown;
};

type OrchestrationEventStatus = 'connecting' | 'live' | 'reconnecting' | 'unavailable';

const EventHistorySchema = z.object({
  events: z.array(z.any()).default([])
}).passthrough();

function useBackendRuntime(enabled = true) {
  return useQuery({
    queryKey: ['backendRuntime'],
    queryFn: async () => invoke<BackendRuntimePayload>('backend_status'),
    refetchInterval: 3_000,
    retry: 1,
    enabled
  });
}

function useCodexAuth(base: string, enabled = true) {
  return useQuery({
    queryKey: ['codexAuth', base],
    queryFn: async () => api<CodexAuthPayload>(base, '/api/codex/auth/status', undefined, 7_500),
    refetchInterval: 20_000,
    enabled
  });
}

function useProviderStatus(base: string, enabled = true) {
  return useQuery<ProviderStatusPayload>({
    queryKey: ['providerStatus', base],
    queryFn: async () => ProviderStatusSchema.parse(await api(base, '/api/orchestration/providers')),
    refetchInterval: 20_000,
    enabled
  });
}

function useOrchestrationEvents(base: string, enabled = true) {
  const [events, setEvents] = useState<OrchestrationEvent[]>([]);
  const [status, setStatus] = useState<OrchestrationEventStatus>('connecting');

  useEffect(() => {
    if (!enabled) {
      setStatus('connecting');
      setEvents([]);
      return;
    }

    let cancelled = false;
    setStatus('connecting');
    setEvents([]);

    api(base, '/api/events', undefined, 5_000)
      .then(payload => {
        if (cancelled) return;
        const parsed = EventHistorySchema.parse(payload);
        setEvents(parsed.events.map(normalizeOrchestrationEvent).filter(isOrchestrationEvent).slice(-100));
      })
      .catch(() => {
        if (!cancelled) setStatus('unavailable');
      });

    const source = new EventSource(joinApiUrl(base, '/api/events/stream'));

    source.onopen = () => {
      if (!cancelled) setStatus('live');
    };

    source.onmessage = message => {
      if (cancelled) return;

      try {
        const event = normalizeOrchestrationEvent(JSON.parse(message.data));
        if (!event) return;
        setStatus('live');
        setEvents(current => [...current.filter(item => item.id !== event.id), event].slice(-100));
      } catch {
        // Ignore malformed stream messages; the backend JSON history remains authoritative.
      }
    };

    source.onerror = () => {
      if (!cancelled) setStatus(current => (current === 'live' ? 'reconnecting' : 'unavailable'));
    };

    return () => {
      cancelled = true;
      source.close();
    };
  }, [base, enabled]);

  return {
    events,
    status,
    lastEvent: events[events.length - 1],
    connected: status === 'live'
  };
}

function normalizeOrchestrationEvent(raw: unknown): OrchestrationEvent | null {
  if (!raw || typeof raw !== 'object') return null;
  const event = raw as Record<string, unknown>;
  const id = typeof event.id === 'string' ? event.id : undefined;
  const type = typeof event.type === 'string' ? event.type : undefined;
  if (!id || !type) return null;
  return event as OrchestrationEvent;
}

function isOrchestrationEvent(event: OrchestrationEvent | null): event is OrchestrationEvent {
  return event !== null;
}

function joinApiUrl(base: string, path: string) {
  const trimmed = base.trim().replace(/\/+$/, '');
  return `${trimmed}${path}`;
}

function providerLabel(provider?: string) {
  if (provider === 'agent_zero') return 'Agent Zero';
  if (provider === 'direct_codex') return 'Direct Codex';
  return 'Symphony';
}

function apiModeLabel(mode: ApiMode) {
  if (mode === 'desktop') return 'desktop bundled backend';
  if (mode === 'proxy') return 'dev proxy';
  if (mode === 'override') return 'manual override';
  if (mode === 'desktop-error') return 'desktop backend failed';
  return 'starting desktop backend';
}

function App() {
  const [desktopBridgeAvailable] = useState(() => hasTauriBridge());
  const [tab, setTab] = useState<Tab>('console');
  const [base, setBase] = useState(() => getApiBase());
  const [apiMode, setApiMode] = useState<ApiMode>(() => getApiBase() ? 'override' : desktopBridgeAvailable ? 'initializing' : 'proxy');
  const [desktopStartupError, setDesktopStartupError] = useState<string | null>(null);
  const apiReady = apiMode !== 'initializing' && apiMode !== 'desktop-error';
  const state = useSymphonyState(base, apiReady);
  const kanban = useKanban(base, apiReady);
  const profilesQuery = useAgentProfiles(base, apiReady);
  const codexAuth = useCodexAuth(base, apiReady);
  const orchestrationEvents = useOrchestrationEvents(base, apiReady);
  const providerStatus = useProviderStatus(base, apiReady);
  const backendRuntime = useBackendRuntime(desktopBridgeAvailable);
  const [debugPayload, setDebugPayload] = useState<string | null>(null);
  const [selectedCardId, setSelectedCardId] = useState<string | null>(null);
  const cards = useMemo(() => makeCardsFromKanban(kanban.data), [kanban.data]);
  const profilesPayload = profilesQuery.data;
  const profiles = useMemo(() => profilesPayload?.profiles ?? [], [profilesPayload?.profiles]);
  const idleMusicians = useMemo(() => makeIdleMusicians(profiles, cards), [profiles, cards]);
  const hasLiveBackendData = Boolean(state.data && kanban.data);
  const hasPollingError = state.isError || kanban.isError;
  const offline = hasPollingError && !hasLiveBackendData;
  const reconnecting = hasPollingError && hasLiveBackendData;
  const [audioEnabled, setAudioEnabled] = useState(false);
  const orchestraAudio = useAgentOrchestra({ enabled: audioEnabled, cards, idleMusicians, offline });
  const selectedCard = cards.find(card => card.id === selectedCardId) || cards[0];

  const invalidateLiveData = () => {
    queryClient.invalidateQueries({ queryKey: ['state'] });
    queryClient.invalidateQueries({ queryKey: ['kanban'] });
  };

  useEffect(() => {
    let cancelled = false;
    const saved = localStorage.getItem('symphony.apiBase');
    if (saved && saved.trim()) {
      setApiMode('override');
      setDesktopStartupError(null);
      return;
    }

    if (!desktopBridgeAvailable) {
      setApiMode('proxy');
      return;
    }

    invoke<BackendRuntimePayload>('ensure_backend_ready')
      .then(status => {
        if (cancelled) return;
        if (status?.baseUrl) {
          setBase(status.baseUrl);
          setApiMode('desktop');
          setDesktopStartupError(null);
        }
      })
      .catch(error => {
        if (cancelled) return;
        setApiMode('desktop-error');
        setDesktopStartupError(error instanceof Error ? error.message : String(error));
      });

    return () => { cancelled = true; };
  }, [desktopBridgeAvailable]);

  useEffect(() => {
    if (selectedCardId && cards.some(card => card.id === selectedCardId)) return;
    setSelectedCardId(cards[0]?.id ?? null);
  }, [cards, selectedCardId]);

  useEffect(() => {
    const type = orchestrationEvents.lastEvent?.type;
    if (!type) return;

    if (
      [
        'tracker.poll.completed',
        'issue.stage.started',
        'issue.stage.blocked',
        'issue.execution.completed',
        'issue.execution.failed',
        'issue.retry.scheduled',
        'operator.issue.move.accepted',
        'operator.issue.action.accepted'
      ].includes(type)
    ) {
      invalidateLiveData();
    }
  }, [orchestrationEvents.lastEvent?.id]);

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
      const isUpdate = Boolean(profile.id && profile.id.trim());
      const payload = isUpdate ? profile : Object.fromEntries(Object.entries(profile).filter(([key, value]) => key !== 'id' && value !== ''));
      const body = JSON.stringify(payload);
      return isUpdate
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
  const selectProvider = useMutation({
    mutationFn: async (provider: string) =>
      ProviderStatusSchema.parse(
        await api(base, '/api/orchestration/providers/select', {
          method: 'POST',
          body: JSON.stringify({ provider })
        })
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providerStatus'] });
      queryClient.invalidateQueries({ queryKey: ['state'] });
      queryClient.invalidateQueries({ queryKey: ['kanban'] });
    }
  });
  const startBundledBackend = useMutation({
    mutationFn: () => invoke<BackendRuntimePayload>('ensure_backend_ready'),
    onSuccess: status => {
      if (status?.baseUrl) {
        setBase(status.baseUrl);
        setApiMode('desktop');
        setDesktopStartupError(null);
      }
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
      invalidateLiveData();
    },
    onError: error => {
      setApiMode('desktop-error');
      setDesktopStartupError(error instanceof Error ? error.message : String(error));
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
    }
  });
  const restartBundledBackend = useMutation({
    mutationFn: () => invoke<BackendRuntimePayload>('backend_restart'),
    onSuccess: status => {
      if (status?.baseUrl) {
        setBase(status.baseUrl);
        setApiMode('desktop');
        setDesktopStartupError(null);
      }
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
      invalidateLiveData();
    },
    onError: error => {
      setApiMode('desktop-error');
      setDesktopStartupError(error instanceof Error ? error.message : String(error));
      queryClient.invalidateQueries({ queryKey: ['backendRuntime'] });
    }
  });
  const backendLogs = useMutation({
    mutationFn: () => invoke<{ logPath?: string; text: string }>('backend_logs', { maxBytes: 65536 })
  });
  const saveBase = (v: string) => {
    const next = v.trim();
    if (next) {
      localStorage.setItem('symphony.apiBase', next);
      setApiMode('override');
    } else {
      localStorage.removeItem('symphony.apiBase');
      if (desktopBridgeAvailable) {
        setApiMode('initializing');
        setDesktopStartupError(null);
        startBundledBackend.mutate();
      } else {
        setApiMode('proxy');
        setDesktopStartupError(null);
      }
    }
    setBase(next);
    queryClient.invalidateQueries();
  };

  const apiStarting = apiMode === 'initializing';
  const apiStartupFailed = apiMode === 'desktop-error';
  const actionBusy = !apiReady || refresh.isPending || debugIssue.isPending || moveIssue.isPending || issueAction.isPending || saveAgentProfile.isPending || deleteAgentProfile.isPending || startCodexLogin.isPending || checkCodexAuth.isPending || logoutCodex.isPending || selectProvider.isPending || startBundledBackend.isPending || restartBundledBackend.isPending;

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
            <span>{apiStarting ? 'starting desktop backend' : apiStartupFailed ? 'backend needs attention' : offline ? 'awaiting orchestra' : reconnecting ? 'holding last cue' : 'conducting live'}</span>
          </div>
        </div>
        <div className="sidebarFooter">
          <span className={apiStarting || apiStartupFailed || offline ? 'statusDot offline' : reconnecting ? 'statusDot reconnecting' : 'statusDot online'} />
          {apiStarting ? 'Starting desktop backend' : apiStartupFailed ? 'Desktop backend failed' : offline ? 'Backend unavailable' : reconnecting ? 'Reconnecting… live cache held' : 'Connected via API'}
        </div>
      </aside>

      <main className="concertWorkspace">
        <ConcertHeader
          offline={offline || apiStartupFailed}
          apiStarting={apiStarting}
          reconnecting={reconnecting}
          eventStatus={orchestrationEvents.status}
          lastEvent={orchestrationEvents.lastEvent}
          eventCount={orchestrationEvents.events.length}
          onRefresh={() => refresh.mutate()}
          busy={actionBusy}
          audioEnabled={audioEnabled}
          onToggleAudio={() => setAudioEnabled(value => !value)}
          orchestraAudio={orchestraAudio}
        />
        <MetricsStrip state={state.data} online={!offline && !apiStarting && !apiStartupFailed} reconnecting={reconnecting} />
        {apiStarting && <StartupBanner />}
        {apiStartupFailed && <DesktopBackendErrorBanner message={desktopStartupError} />}
        {offline && !apiStartupFailed && <OfflineBanner base={base} />}
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
              storage={profilesPayload?.storage}
              idleMusicians={idleMusicians}
              loading={profilesQuery.isLoading}
              busy={actionBusy}
              saveError={saveAgentProfile.error instanceof Error ? saveAgentProfile.error.message : undefined}
              deleteError={deleteAgentProfile.error instanceof Error ? deleteAgentProfile.error.message : undefined}
              setSelectedCardId={setSelectedCardId}
              onSaveProfile={profile => saveAgentProfile.mutateAsync(profile)}
              onDeleteProfile={id => deleteAgentProfile.mutateAsync(id)}
            />
          )}
          {tab === 'workflow' && <WorkflowPanel base={base} state={state.data} cards={cards} profiles={profiles} enabled={apiReady} />}
          {tab === 'ledger' && (
            <EventLedger
              events={orchestrationEvents.events}
              status={orchestrationEvents.status}
              providerStatus={providerStatus.data}
            />
          )}
          {tab === 'safety' && <SafetyPanel />}
          {tab === 'settings' && (
            <SettingsPanel
              base={base}
              saveBase={saveBase}
              codexAuth={codexAuth.data}
              codexLoading={codexAuth.isLoading}
              codexError={codexAuth.error instanceof Error ? codexAuth.error.message : codexAuth.isError ? 'Unable to reach Codex auth endpoint.' : undefined}
              codexBusy={startCodexLogin.isPending || checkCodexAuth.isPending || logoutCodex.isPending}
              providerStatus={providerStatus.data}
              providerError={providerStatus.error instanceof Error ? providerStatus.error.message : providerStatus.isError ? 'Unable to reach provider endpoint.' : undefined}
              providerSelectError={selectProvider.error instanceof Error ? selectProvider.error.message : undefined}
              providerBusy={selectProvider.isPending}
              apiMode={apiMode}
              desktopStartupError={desktopStartupError}
              desktopBridgeAvailable={desktopBridgeAvailable}
              backendRuntime={backendRuntime.data}
              backendRuntimeError={desktopBridgeAvailable ? backendRuntime.error instanceof Error ? backendRuntime.error.message : backendRuntime.isError ? 'Tauri backend manager unavailable.' : undefined : undefined}
              backendBusy={startBundledBackend.isPending || restartBundledBackend.isPending}
              backendLogs={backendLogs.data}
              onStartBackend={() => startBundledBackend.mutate()}
              onRestartBackend={() => restartBundledBackend.mutate()}
              onRefreshBackend={() => queryClient.invalidateQueries({ queryKey: ['backendRuntime'] })}
              onLoadBackendLogs={() => backendLogs.mutate()}
              onSelectProvider={provider => selectProvider.mutate(provider)}
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
  apiStarting,
  reconnecting,
  eventStatus,
  lastEvent,
  eventCount,
  onRefresh,
  busy,
  audioEnabled,
  onToggleAudio,
  orchestraAudio
}: {
  offline: boolean;
  apiStarting: boolean;
  reconnecting: boolean;
  eventStatus: OrchestrationEventStatus;
  lastEvent?: OrchestrationEvent;
  eventCount: number;
  onRefresh: () => void;
  busy: boolean;
  audioEnabled: boolean;
  onToggleAudio: () => void;
  orchestraAudio: OrchestraAudioState;
}) {
  const eventLive = eventStatus === 'live';
  const eventReconnecting = eventStatus === 'reconnecting';
  const eventStatusLabel = apiStarting
    ? 'events waiting for backend'
    : eventLive
    ? `${providerLabel(lastEvent?.provider)} events live`
    : eventReconnecting
      ? 'events reconnecting'
      : eventStatus === 'connecting'
        ? 'events connecting'
        : 'events unavailable';

  return (
    <header className="concertHeader pixelPanel">
      <div>
        <p className="eyebrow">Live score for autonomous work</p>
        <h1>Conductor View</h1>
        <p className="subtle">{apiStarting ? 'Starting the bundled desktop backend' : offline ? 'The pit is quiet until the backend returns' : reconnecting ? 'Holding the last live score while the backend reconnects' : 'Real Linear issues conducted by Codex agents'} · musicians, movements, and generated score</p>
      </div>
      <div className="actions">
        <span className={`pill eventPill ${eventLive ? 'active' : eventReconnecting ? 'warning' : 'neutral'}`} title={lastEvent?.message || 'Provider-neutral orchestration event stream'}>
          <Activity size={14} /> {eventStatusLabel} · {eventCount}
        </span>
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

function StartupBanner() {
  return (
    <div className="banner startupBanner pixelPanel">
      <Server size={18} />
      <span>Starting the managed Symphony backend for this desktop window. API reads and agent actions will enable when the local runtime is healthy.</span>
    </div>
  );
}

function DesktopBackendErrorBanner({ message }: { message: string | null }) {
  return (
    <div className="banner errorBanner pixelPanel">
      <AlertTriangle size={18} />
      <span>Desktop backend startup failed{message ? `: ${message}` : '.'} Open Settings to restart the bundled backend or inspect logs.</span>
    </div>
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

type StageStation = { column: string; id: string; label: string; kind: string; x: number; y: number };

const stationMeta: StageStation[] = [
  { column: 'Ready', id: 'queue', label: 'Score Queue', kind: 'queue', x: 17, y: 70 },
  { column: 'In Progress', id: 'strings', label: 'Strings / Active', kind: 'active', x: 38, y: 36 },
  { column: 'Human Review', id: 'podium', label: 'Conductor Review', kind: 'review', x: 61, y: 35 },
  { column: 'Retry', id: 'tuning', label: 'Tuning Retry', kind: 'retry', x: 76, y: 68 },
  { column: 'Blocked', id: 'dissonance', label: 'Dissonance', kind: 'blocked', x: 24, y: 39 },
  { column: 'Done', id: 'finale', label: 'Finale Archive', kind: 'done', x: 86, y: 82 }
];

const sectionStations: Record<string, StageStation> = {
  Strings: stationMeta[1],
  Woodwinds: { column: 'In Progress', id: 'woodwinds-active', label: 'Woodwinds / Active', kind: 'active', x: 31, y: 54 },
  Brass: { column: 'In Progress', id: 'brass-active', label: 'Brass / Active', kind: 'active', x: 68, y: 53 },
  Percussion: { column: 'Retry', id: 'percussion-active', label: 'Percussion / Active', kind: 'retry', x: 77, y: 68 },
  Piano: { column: 'Human Review', id: 'piano-active', label: 'Piano / Judge', kind: 'review', x: 55, y: 61 },
  Bells: { column: 'Done', id: 'bells-active', label: 'Bells / Finale', kind: 'done', x: 86, y: 72 }
};

const sectionSeatAnchors: Record<string, { x: number; y: number }> = {
  Strings: { x: 41, y: 65 },
  Woodwinds: { x: 31, y: 54 },
  Brass: { x: 68, y: 53 },
  Percussion: { x: 77, y: 68 },
  Piano: { x: 55, y: 61 },
  Bells: { x: 86, y: 72 }
};

const stageSeatOffsets: Record<string, { x: number; y: number }> = {
  'front-left': { x: -8, y: -2 },
  'front-center': { x: 0, y: -4 },
  'front-right': { x: 8, y: -2 },
  'mid-left': { x: -6, y: 4 },
  'mid-center': { x: 0, y: 4 },
  'mid-right': { x: 6, y: 4 },
  'back-left': { x: -7, y: 10 },
  'back-center': { x: 0, y: 10 },
  'back-right': { x: 7, y: 10 }
};

const renderedStations: StageStation[] = [
  ...stationMeta,
  ...Object.values(sectionStations).filter(station => !stationMeta.some(base => base.id === station.id))
];

function stationForCard(card: Card) {
  const section = displaySection(card.stagePosition?.section || card.section);
  if (card.agentProfileId && sectionStations[section]) return sectionStations[section];
  return stationMeta.find(item => item.column === card.column) || stationMeta[0];
}

function displaySection(section?: string) {
  const lower = String(section || '').toLowerCase();
  if (lower.includes('timpani') || lower.includes('drum')) return 'Percussion';
  const match = orchestraSections.find(item => item.toLowerCase() === String(section || '').toLowerCase());
  return match || 'Strings';
}

function sectionClass(section?: string) {
  return displaySection(section).toLowerCase();
}

function sectionSlug(section?: string) {
  return displaySection(section).toLowerCase();
}

function defaultSeatForSection(section?: string) {
  const seats: Record<string, string> = {
    Strings: 'front-center',
    Woodwinds: 'mid-left',
    Brass: 'mid-right',
    Percussion: 'back-right',
    Piano: 'mid-center',
    Bells: 'back-center'
  };
  return seats[displaySection(section)] || 'front-center';
}

function stageSeatCoordinates(position: StagePosition | undefined, fallbackSection: string, index: number) {
  const section = displaySection(position?.section || fallbackSection);
  const anchor = sectionSeatAnchors[section] || sectionSeatAnchors.Strings;
  const seatName = stageSeats.includes(String(position?.seat || '').toLowerCase())
    ? String(position?.seat).toLowerCase()
    : defaultSeatForSection(section);
  const seat = stageSeatOffsets[seatName] || stageSeatOffsets[defaultSeatForSection(section)];
  const rawX = position?.x ?? anchor.x + seat.x;
  const rawY = position?.y ?? anchor.y + seat.y;
  const offsetX = ((index % 3) - 1) * 2;
  const offsetY = Math.floor(index % 6 / 3) * 3;
  return { x: clamp(rawX + offsetX, 8, 92), y: clamp(rawY + offsetY, 31, 86) };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

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
  const counts = Object.fromEntries(
    renderedStations.map(station => [
      station.id,
      cards.filter(card => stationForCard(card).id === station.id).length
    ])
  );
  const movements = movementSummary(cards);

  return (
    <div className="orchestraDeck">
      <section className="stageMap pixelPanel" aria-label="Animated orchestra floor">
        <div className="stageBackdrop" aria-hidden="true">
          <div className="operaCurtain curtainLeft" />
          <div className="operaCurtain curtainRight" />
          <div className="footlights" />
          <div className="backWall">
            <span className="hallVault" />
            <span className="goldColumn columnLeft" />
            <span className="goldColumn columnRight" />
            <span className="sideBox sideBoxLeft"><i /><i /></span>
            <span className="sideBox sideBoxRight"><i /><i /></span>
            <span className="organLoft"><i /><i /><i /><i /><i /><i /><i /></span>
            <span className="balcony balconyLeft"><i /><i /><i /></span>
            <span className="balcony balconyCenter"><i /><i /><i /><i /></span>
            <span className="balcony balconyRight"><i /><i /><i /></span>
            <span className="prosceniumArch"><b>CODEX HALL</b></span>
            <span className="chandelier"><i /><i /><i /><i /></span>
          </div>
          <div className="stageApron" />
          <div className="stageFloor" />
          <div className="pitRail" />
        </div>
        <MovementRibbon movements={movements} activeVoices={orchestraAudio.activeVoices} />
        <Conductor active={cards.length > 0} />
        <CueLines cards={cards} />
        {renderedStations.map(station => (
          <Station key={station.id} station={station} count={counts[station.id] || 0} />
        ))}
        {cards.length === 0 && <EmptyHouse />}
        {cards.map((card, index) => {
          const station = stationForCard(card);
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
        const station = stationForCard(card);
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

function Station({ station, count }: { station: StageStation; count: number }) {
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
  station: StageStation;
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
  const seat = card.agentProfileId || card.stagePosition
    ? stageSeatCoordinates(card.stagePosition, card.section, index)
    : { x: station.x + offsetX, y: station.y + offsetY + 8 };
  const instrument = instrumentFor(card.agent, card.status, card.instrumentName);
  const status = statusClass(card.status);
  const chair = (hashString(card.backendId) % 4) + 1;

  return (
    <article
      className={`performer performer-${status} ${selected ? 'selected' : ''}`}
      style={{ left: `${seat.x}%`, top: `${seat.y}%` }}
      onClick={onSelect}
    >
      <div className="performerShadow" />
      <div className={`pixelPerson musician ${status} section-${sectionClass(card.section)}`}><span className="head" /><span className="body" /><span className="legs" /><span className="instrument">{instrument}</span></div>
      <div className="musicNote">♪</div>
      <div className="openScore"><span /> <span /> <b>{card.movement.replace(' · ', ' ')}</b></div>
      <div className="taskSlip">
        <span className="ticket">{card.identifier}</span>
        <b>{card.title}</b>
        <small>{card.instrumentName} · {card.section} · chair {chair}</small>
        <small>{card.agent}{card.agentRole ? ` · ${card.agentRole}` : ''} · {card.turns} turns · {card.tokens.toLocaleString()} notes</small>
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
  const seat = idleSeatFor(musician.section, musician.stagePosition, index);
  return (
    <article className={`performer idlePerformer ${musician.status === 'disabled' ? 'disabled' : ''}`} style={{ left: `${seat.x}%`, top: `${seat.y}%` }}>
      <div className="performerShadow" />
      <div className={`pixelPerson musician idle section-${sectionClass(musician.section)}`}><span className="head" /><span className="body" /><span className="legs" /><span className="instrument">{instrumentFor(musician.agent, musician.status, musician.instrumentName)}</span></div>
      <div className="taskSlip idleSlip">
        <span className="ticket">{musician.status.toUpperCase()}</span>
        <b>{musician.agent}</b>
        <small>{musician.instrumentName} · {musician.section}</small>
        <small>{musician.role} · waiting for assignment</small>
      </div>
    </article>
  );
}

function idleSeatFor(section: string, position: StagePosition | undefined, index: number) {
  return stageSeatCoordinates(position, section, index);
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


function instrumentFor(agent: string, status: string, instrumentName = '') {
  const s = `${agent} ${status} ${instrumentName}`.toLowerCase();
  if (s.includes('timpani') || s.includes('drum') || s.includes('percussion') || s.includes('backoff') || s.includes('retry')) return '🥁';
  if (s.includes('piano') || s.includes('review') || s.includes('judge')) return '🎹';
  if (s.includes('horn') || s.includes('brass') || s.includes('guardian') || s.includes('block')) return '📯';
  if (s.includes('trumpet') || s.includes('finish') || s.includes('done')) return '🎺';
  if (s.includes('violin') || s.includes('viola') || s.includes('cello') || s.includes('builder') || s.includes('run')) return '🎻';
  if (s.includes('glockenspiel') || s.includes('bell')) return '🔔';
  return '🎼';
}

function StatusPill({ status }: { status: string }) {
  const s = status.toLowerCase();
  const Icon = s.includes('block') ? AlertTriangle : s.includes('done') ? CheckCircle2 : s.includes('retry') ? Clock : s.includes('judge') || s.includes('review') ? BrainCircuit : s.includes('refin') || s.includes('execut') || s.includes('run') ? PlayCircle : CircleDot;
  return <span className={`pill ${statusClass(status)}`}><Icon size={13} />{status}</span>;
}

function statusClass(status: string) {
  const s = status.toLowerCase();
  if (s.includes('block') || s.includes('fail') || s.includes('error')) return 'danger';
  if (s.includes('retry')) return 'warning';
  if (s.includes('done') || s.includes('complete')) return 'success';
  if (s.includes('judge') || s.includes('review')) return 'review';
  if (s.includes('refin') || s.includes('execut') || s.includes('run') || s.includes('ready')) return 'active';
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
  storage,
  idleMusicians,
  loading,
  busy,
  saveError,
  deleteError,
  setSelectedCardId,
  onSaveProfile,
  onDeleteProfile
}: {
  cards: Card[];
  profiles: AgentProfile[];
  storage?: z.infer<typeof AgentStorageSchema>;
  idleMusicians: IdleMusician[];
  loading: boolean;
  busy: boolean;
  saveError?: string;
  deleteError?: string;
  setSelectedCardId: (id: string) => void;
  onSaveProfile: (profile: AgentProfile) => Promise<unknown>;
  onDeleteProfile: (id: string) => Promise<unknown>;
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
        {storage && <p className="subtle">Profile storage: {storage.writable === false ? 'not writable' : 'writable'} · {storage.path || 'unknown path'}</p>}
        {(saveError || deleteError) && <p className="formError">{saveError || deleteError}</p>}
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
      <AgentProfileForm profile={editing} busy={busy} onCancel={() => setEditing(null)} onSave={async profile => { await onSaveProfile(profile); setEditing(null); }} onDelete={async id => { await onDeleteProfile(id); setEditing(null); }} />
    </section>
  );
}

function AgentProfileForm({ profile, busy, onSave, onCancel, onDelete }: { profile: AgentProfile | null; busy: boolean; onSave: (profile: AgentProfile) => Promise<void>; onCancel: () => void; onDelete: (id: string) => Promise<void> }) {
  const [draft, setDraft] = useState<AgentProfile>(profile || emptyAgentProfile());
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setDraft(profile || emptyAgentProfile()); setError(null); }, [profile]);
  const update = <K extends keyof AgentProfile>(key: K, value: AgentProfile[K]) => setDraft(prev => ({ ...prev, [key]: value }));
  const draftStage = stagePosition(draft.stage_position) || { section: sectionSlug(draft.section), seat: defaultSeatForSection(draft.section) };
  const draftMusic = musicProfile(draft.music) || { motif: '', dynamic: 'mezzo-piano', register: 'middle' };
  const updateSection = (section: string) => setDraft(prev => {
    const currentStage = stagePosition(prev.stage_position) || {};
    const previousStageSection = sectionSlug(currentStage.section || prev.section);
    const shouldFollowSection = !currentStage.section || previousStageSection === sectionSlug(prev.section);
    return {
      ...prev,
      section,
      stage_position: {
        ...currentStage,
        section: shouldFollowSection ? sectionSlug(section) : previousStageSection,
        seat: shouldFollowSection ? defaultSeatForSection(section) : currentStage.seat || defaultSeatForSection(section)
      }
    };
  });
  const updateStage = (patch: StagePosition) => setDraft(prev => {
    const current = stagePosition(prev.stage_position) || {};
    return { ...prev, stage_position: { ...current, ...patch } };
  });
  const updateMusic = (patch: MusicProfile) => setDraft(prev => {
    const current = musicProfile(prev.music) || {};
    return { ...prev, music: { ...current, ...patch } };
  });
  const submit = async () => {
    try {
      setError(null);
      const payload = AgentProfileSchema.parse({ ...draft, capabilities: Array.isArray(draft.capabilities) ? draft.capabilities : String(draft.capabilities || '').split(',').map(v => v.trim()).filter(Boolean) });
      if (!payload.name.trim()) throw new Error('Name is required');
      await onSave(payload);
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
      <label>Section</label><select value={draft.section} onChange={e => updateSection(e.target.value)}>{orchestraSections.map(section => <option key={section}>{section}</option>)}</select>
      <label>Instrument</label><input value={draft.instrument_name} onChange={e => update('instrument_name', e.target.value)} placeholder="Violin" />
      <label>Stage section</label><select value={sectionSlug(draftStage.section || draft.section)} onChange={e => updateStage({ section: e.target.value, seat: defaultSeatForSection(e.target.value) })}>{orchestraSections.map(section => <option key={section} value={sectionSlug(section)}>{section}</option>)}</select>
      <label>Stage seat</label><select value={draftStage.seat || defaultSeatForSection(draftStage.section || draft.section)} onChange={e => updateStage({ seat: e.target.value })}>{stageSeats.map(seat => <option key={seat} value={seat}>{seat.replace('-', ' ')}</option>)}</select>
      <label>Music motif</label><input value={draftMusic.motif || ''} onChange={e => updateMusic({ motif: e.target.value })} placeholder="Solo entrance" />
      <label>Dynamic</label><select value={draftMusic.dynamic || 'mezzo-piano'} onChange={e => updateMusic({ dynamic: e.target.value })}>{musicDynamics.map(dynamic => <option key={dynamic}>{dynamic}</option>)}</select>
      <label>Register</label><select value={draftMusic.register || 'middle'} onChange={e => updateMusic({ register: e.target.value })}>{musicRegisters.map(register => <option key={register}>{register.replace('-', ' ')}</option>)}</select>
      <label>Max concurrent tasks</label><input type="number" min="1" value={draft.max_concurrent_tasks} onChange={e => update('max_concurrent_tasks', Number(e.target.value || 1))} />
      <label>Model</label><input value={draft.model} onChange={e => update('model', e.target.value)} placeholder="optional" />
      <label>Workspace key</label><input value={draft.workspace_key} onChange={e => update('workspace_key', e.target.value)} placeholder="agent-builder" />
      <label>Capabilities comma separated</label><input value={(draft.capabilities || []).join(', ')} onChange={e => update('capabilities', e.target.value.split(',').map(v => v.trim()).filter(Boolean))} placeholder="frontend, tests, review" />
      <label>Description</label><textarea value={draft.description} onChange={e => update('description', e.target.value)} />
      <label>Instructions</label><textarea className="tall" value={draft.instructions} onChange={e => update('instructions', e.target.value)} />
      <label className="checkRow"><input type="checkbox" checked={draft.enabled} onChange={e => update('enabled', e.target.checked)} /> Enabled / visible as idle musician</label>
      {error && <p className="formError">{error}</p>}
      <div className="formActions"><button className="button primary" disabled={busy} onClick={submit}>Save profile</button><button className="button secondary" disabled={busy} onClick={onCancel}>Cancel</button>{draft.id && <button className="button danger" disabled={busy} onClick={async () => { try { setError(null); await onDelete(draft.id); } catch (err) { setError(err instanceof Error ? err.message : String(err)); } }}>Delete</button>}</div>
    </aside>
  );
}

function WorkflowPanel({ base, state, cards, profiles, enabled }: { base: string; state?: SymphonyState; cards: Card[]; profiles: AgentProfile[]; enabled: boolean }) {
  const templatesQuery = useWorkflowTemplates(base, enabled);
  const filesQuery = useWorkflowFiles(base, enabled);
  const [templateId, setTemplateId] = useState('linear_codex_judge_refiner');
  const [targetPath, setTargetPath] = useState('generated-workflow/WORKFLOW.md');
  const [overwrite, setOverwrite] = useState(false);
  const [name, setName] = useState('symphony-orchestra-workflow');
  const [objective, setObjective] = useState('Coordinate real work through generator, builder, judge, and refiner phases.');
  const [generatorProfileId, setGeneratorProfileId] = useState('');
  const [builderProfileId, setBuilderProfileId] = useState('');
  const [judgeProfileId, setJudgeProfileId] = useState('');
  const [refinerProfileId, setRefinerProfileId] = useState('');
  const [validatorProfileId, setValidatorProfileId] = useState('');
  const [draft, setDraft] = useState('');
  const [validation, setValidation] = useState<WorkflowValidation | null>(null);
  const [preview, setPreview] = useState<WorkflowPreview | null>(null);
  const [operationLog, setOperationLog] = useState<string[]>([]);
  const [workflowError, setWorkflowError] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const selectedTemplate = templatesQuery.data?.find(t => t.id === templateId) || templatesQuery.data?.[0];
  const enabledProfiles = profiles.filter(profile => profile.enabled);
  const usesValidator = templateId === 'repository_orchestra';
  const assignmentSelections = [
    { role: 'Generator', id: generatorProfileId },
    { role: 'Builder', id: builderProfileId },
    { role: 'Judge', id: judgeProfileId },
    { role: 'Refiner', id: refinerProfileId },
    ...(usesValidator ? [{ role: 'Validator', id: validatorProfileId }] : [])
  ].filter(selection => selection.id);
  const assignmentIssues = assignmentSelections.flatMap(selection => {
    const profile = profiles.find(item => item.id === selection.id);
    if (!profile) return [`${selection.role} profile is no longer available.`];
    if (!profile.enabled) return [`${selection.role} profile ${profile.name} is disabled.`];
    return [];
  });
  const workflowOverrides = () => Object.fromEntries(
    Object.entries({
      name,
      objective,
      max_concurrent_agents: '2',
      poll_interval_ms: '30000',
      generator_profile: generatorProfileId,
      builder_profile: builderProfileId,
      judge_profile: judgeProfileId,
      refiner_profile: refinerProfileId,
      validator_profile: usesValidator ? validatorProfileId : ''
    }).filter(([, value]) => String(value || '').trim() !== '')
  );
  const log = (message: string) => setOperationLog(prev => [message, ...prev].slice(0, 8));
  const fail = (label: string, err: unknown) => {
    const message = `${label}: ${err instanceof Error ? err.message : String(err)}`;
    setWorkflowError(message);
    log(message);
  };

  const generate = useMutation({
    mutationFn: async () => WorkflowGenerateSchema.parse(await api(base, '/api/workflows/generate', {
      method: 'POST',
      body: JSON.stringify({ template_id: templateId, overrides: workflowOverrides() })
    }, 8000)),
    onSuccess: data => {
      setWorkflowError(null);
      setDraft(data.content);
      setValidation(data.validation || null);
      setPreview(null);
      log(`Generated ${data.filename || 'WORKFLOW.md'} from ${data.template_id || templateId}`);
      if (data.agent_profile_changes?.count) log(`Stage agents ready: ${data.agent_profile_changes.count} profiles created or refreshed.`);
      queryClient.invalidateQueries({ queryKey: ['agentProfiles', base] });
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
    mutationFn: async () => api<Record<string, unknown>>(base, '/api/workflows', { method: 'POST', body: JSON.stringify({ path: targetPath, content: draft, template_id: templateId, overwrite }) }, 8000),
    onSuccess: data => {
      setWorkflowError(null);
      const activationHint = data.reload_required ? ' · reload runtime to activate' : data.restart_required ? ' · backend restart required to activate' : '';
      log(`Saved ${String(data.path || targetPath)}${activationHint}`);
      const changes = data.agent_profile_changes as { count?: number } | undefined;
      if (changes?.count) log(`Stage agents ready: ${changes.count} profiles created or refreshed.`);
      queryClient.invalidateQueries({ queryKey: ['workflowFiles', base] });
      queryClient.invalidateQueries({ queryKey: ['agentProfiles', base] });
    },
    onError: err => fail('Save failed', err)
  });

  const moveWorkflow = useMutation({
    mutationFn: async () => api<Record<string, unknown>>(base, '/api/workflows/move', { method: 'POST', body: JSON.stringify({ source_path: targetPath, destination_path: targetPath.replace(/WORKFLOW\.md$/, 'archived/WORKFLOW.md'), overwrite }) }, 8000),
    onSuccess: data => { setWorkflowError(null); log(`Moved workflow to ${String(data.destination_path || 'destination')}`); queryClient.invalidateQueries({ queryKey: ['workflowFiles', base] }); },
    onError: err => fail('Move failed', err)
  });

  const reloadWorkflow = useMutation({
    mutationFn: async () => api<Record<string, unknown>>(base, '/api/workflow/reload', { method: 'POST', body: '{}' }, 10_000),
    onSuccess: data => {
      setWorkflowError(null);
      log(String(data.message || 'Runtime workflow reloaded.'));
      const changes = data.agent_profile_changes as { count?: number } | undefined;
      if (changes?.count) log(`Stage agents ready: ${changes.count} profiles created or refreshed.`);
      queryClient.invalidateQueries({ queryKey: ['workflowFiles', base] });
      queryClient.invalidateQueries({ queryKey: ['agentProfiles', base] });
      queryClient.invalidateQueries({ queryKey: ['state', base] });
      queryClient.invalidateQueries({ queryKey: ['providerStatus', base] });
    },
    onError: err => fail('Reload failed', err)
  });

  const busy = !enabled || generate.isPending || validateDraft.isPending || previewDraft.isPending || writeDraft.isPending || moveWorkflow.isPending || reloadWorkflow.isPending;
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
        {!enabled && <p className="formError">Desktop backend is starting; workflow operations are disabled until the local runtime is ready.</p>}

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
        <div className="workflowAssignmentGrid">
          <ProfileSelect label="Generator" value={generatorProfileId} onChange={setGeneratorProfileId} profiles={enabledProfiles} />
          <ProfileSelect label="Builder" value={builderProfileId} onChange={setBuilderProfileId} profiles={enabledProfiles} />
          <ProfileSelect label="Judge" value={judgeProfileId} onChange={setJudgeProfileId} profiles={enabledProfiles} />
          <ProfileSelect label="Refiner" value={refinerProfileId} onChange={setRefinerProfileId} profiles={enabledProfiles} />
          {usesValidator && <ProfileSelect label="Validator" value={validatorProfileId} onChange={setValidatorProfileId} profiles={enabledProfiles} />}
        </div>
        {assignmentIssues.length > 0 && <div className="assignmentWarnings">{assignmentIssues.map(issue => <p key={issue}>{issue}</p>)}</div>}
        <div className="formActions">
          <button className="button primary" disabled={busy || assignmentIssues.length > 0} onClick={() => generate.mutate()}><Music2 size={15} />Generate</button>
          <button className="button secondary" title={!draft ? 'Generate or paste WORKFLOW.md content first.' : 'Run backend workflow validation/judge.'} disabled={busy || !draft} onClick={() => validateDraft.mutate()}>Judge</button>
          <button className="button secondary" disabled={busy || !draft} onClick={() => previewDraft.mutate()}>Preview</button>
        </div>
        <textarea className="workflowEditor" value={draft} onChange={e => { setDraft(e.target.value); setValidation(null); setPreview(null); }} placeholder="Generate or paste WORKFLOW.md content here. Missing facts should stay unresolved, not invented." />
      </div>

      <aside className="workflowInspector pixelPanel">
        <div className="panelHeader"><div><p className="eyebrow">Rehearsal Desk</p><h2>Judge / Refiner / Location</h2></div></div>
        <div className="targetPreview">
          <b>Backend-managed root</b>
          <code>{filesQuery.data?.root || (enabled ? 'loading…' : 'waiting for desktop backend')}</code>
          <small>Tauri stays an HTTP client; file writes are backend-mediated and path-safe.</small>
        </div>
        <label className="checkRow"><input type="checkbox" checked={overwrite} onChange={e => setOverwrite(e.target.checked)} /> Allow overwrite after explicit confirmation</label>
        <div className="formActions">
          <button className="button primary" disabled={busy || !draft} onClick={() => writeDraft.mutate()}>Save WORKFLOW.md</button>
          <button className="button secondary" disabled={busy} onClick={() => reloadWorkflow.mutate()}>Reload runtime</button>
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

function ProfileSelect({ label, value, onChange, profiles }: { label: string; value: string; onChange: (value: string) => void; profiles: AgentProfile[] }) {
  return (
    <label>{label}
      <select value={value} onChange={event => onChange(event.target.value)}>
        <option value="">Template default</option>
        {profiles.map(profile => (
          <option key={profile.id} value={profile.id}>{profile.name} · {profile.instrument_name} · {profile.section}</option>
        ))}
      </select>
    </label>
  );
}

function EventLedger({
  events,
  status,
  providerStatus
}: {
  events: OrchestrationEvent[];
  status: OrchestrationEventStatus;
  providerStatus?: ProviderStatusPayload;
}) {
  const activeProvider = providerStatus?.providers.find(provider => provider.active);
  const latest = [...events].slice(-40).reverse();

  return (
    <section className="ledgerPage">
      <div className="doc pixelPanel ledgerHero">
        <div>
          <p className="eyebrow">Orchestration Ledger</p>
          <h2><Activity size={20} /> Live Contract</h2>
          <p className="subtle">{providerLabel(activeProvider?.id || providerStatus?.active_provider)} · contract v{providerStatus?.contract_version || 1} · {status}</p>
        </div>
        <span className={`pill ${status === 'live' ? 'active' : status === 'reconnecting' ? 'warning' : 'neutral'}`}>{events.length} events</span>
      </div>

      <div className="ledgerGrid">
        <div className="doc pixelPanel">
          <div className="panelHeader">
            <div>
              <p className="eyebrow">Providers</p>
              <h2><SlidersHorizontal size={20} /> Switchboard</h2>
            </div>
            <span className={`pill ${providerStatus?.status === 'ready' ? 'success' : 'warning'}`}>{providerStatus?.status || 'checking'}</span>
          </div>
          <div className="providerCards">
            {(providerStatus?.providers || []).map(provider => (
              <ProviderCard key={provider.id} provider={provider} />
            ))}
            {(providerStatus?.providers || []).length === 0 && <p className="subtle">Provider status unavailable.</p>}
          </div>
        </div>

        <div className="doc pixelPanel ledgerList">
          <div className="panelHeader">
            <div>
              <p className="eyebrow">Events</p>
              <h2><FileText size={20} /> Timeline</h2>
            </div>
            <span className="pill neutral">{latest[0]?.type || 'waiting'}</span>
          </div>
          <div className="eventRows">
            {latest.map(event => <EventRow key={event.id} event={event} />)}
            {latest.length === 0 && <p className="subtle">No orchestration events received yet.</p>}
          </div>
        </div>
      </div>
    </section>
  );
}

function ProviderCard({
  provider,
  busy,
  onSelect
}: {
  provider: Provider;
  busy?: boolean;
  onSelect?: (provider: string) => void;
}) {
  const blockedReason = provider.blocked_reason || provider.message || 'Provider is not selectable yet.';
  return (
    <div className={`providerCard ${provider.active ? 'active' : ''}`}>
      <div>
        <b>{provider.name}</b>
        <span>{provider.active ? 'active' : provider.default ? 'default' : 'optional'}</span>
      </div>
      <StatusPill status={provider.status} />
      <dl className="definitionList compact">
        {provider.command && <div><dt>Command</dt><dd>{provider.command}</dd></div>}
        {provider.endpoint && <div><dt>Endpoint</dt><dd>{provider.endpoint}</dd></div>}
        {provider.auth_source && <div><dt>Auth</dt><dd>{provider.auth_source}</dd></div>}
        {provider.message && <div><dt>State</dt><dd>{provider.message}</dd></div>}
      </dl>
      {onSelect && (
        <button
          className={provider.active ? 'button secondary' : 'button primary'}
          disabled={busy || provider.active || !provider.selectable}
          title={!provider.selectable && !provider.active ? blockedReason : `Use ${provider.name}`}
          onClick={() => onSelect(provider.id)}
        >
          <SlidersHorizontal size={14} />
          {provider.active ? 'Active Provider' : provider.selectable ? `Use ${provider.name}` : 'Activation Blocked'}
        </button>
      )}
      {!provider.selectable && !provider.active && <p className="subtle">{blockedReason}</p>}
    </div>
  );
}

function EventRow({ event }: { event: OrchestrationEvent }) {
  return (
    <div className="eventRow">
      <div className="eventMain">
        <span className={`eventDot ${statusClass(event.status || event.type)}`} />
        <div>
          <b>{event.type}</b>
          <small>{providerLabel(event.provider)} · {event.stage || 'system'} · {formatEventTime(event.occurred_at)}</small>
        </div>
      </div>
      <p>{event.message || event.action || 'Event received'}</p>
      {(event.issue_identifier || event.issue_id) && <code>{event.issue_identifier || event.issue_id}</code>}
    </div>
  );
}

function formatEventTime(value?: string) {
  if (!value) return 'pending';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
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
  providerStatus,
  providerError,
  providerSelectError,
  providerBusy,
  apiMode,
  desktopStartupError,
  desktopBridgeAvailable,
  backendRuntime,
  backendRuntimeError,
  backendBusy,
  backendLogs,
  onStartBackend,
  onRestartBackend,
  onRefreshBackend,
  onLoadBackendLogs,
  onSelectProvider,
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
  providerStatus?: ProviderStatusPayload;
  providerError?: string;
  providerSelectError?: string;
  providerBusy: boolean;
  apiMode: ApiMode;
  desktopStartupError: string | null;
  desktopBridgeAvailable: boolean;
  backendRuntime?: BackendRuntimePayload;
  backendRuntimeError?: string;
  backendBusy: boolean;
  backendLogs?: { logPath?: string; text: string };
  onStartBackend: () => void;
  onRestartBackend: () => void;
  onRefreshBackend: () => void;
  onLoadBackendLogs: () => void;
  onSelectProvider: (provider: string) => void;
  onStartCodexLogin: () => void;
  onCheckCodex: () => void;
  onLogoutCodex: () => void;
}) {
  const [v, setV] = useState(base);
  useEffect(() => setV(base), [base]);
  const codexState = String(codexAuth?.state || codexAuth?.status || '');
  const codexConnected = Boolean(codexAuth?.authenticated || codexAuth?.connected || codexState === 'authenticated' || codexState === 'connected');
  const codexAvailable = Boolean(codexAuth?.cli_available ?? codexAuth?.available ?? false);
  const codexVersion = String(codexAuth?.cli_version || codexAuth?.version || 'unknown');
  const codexCommand = String(codexAuth?.configured_command || codexAuth?.command || 'codex');
  const codexStatus = codexLoading
    ? 'checking…'
    : codexError
      ? 'backend unavailable'
      : codexConnected
        ? 'Codex Pro connected'
        : codexAvailable
          ? 'sign-in needed'
          : 'Codex CLI missing';
  const backendControlsDisabled = backendBusy || !desktopBridgeAvailable;
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
          <div><span>Mode</span><b>{apiModeLabel(apiMode)}</b></div>
          <div><span>Tauri bridge</span><b>{desktopBridgeAvailable ? 'available' : 'not in this window'}</b></div>
          <div><span>Managed</span><b>{backendRuntime?.managed ? 'yes' : 'not yet'}</b></div>
          <div><span>Healthy</span><b>{backendRuntime?.healthy ? 'yes' : 'pending'}</b></div>
          <div><span>Port</span><b>{backendRuntime?.port || 'auto'}</b></div>
          <div><span>Source</span><b>{String(backendRuntime?.source || 'bundled backend')}</b></div>
        </div>
        {desktopStartupError && <p className="formError">{desktopStartupError}</p>}
        {backendRuntimeError && <p className="formError">{backendRuntimeError}</p>}
        {backendRuntime?.lastError && <p className="formError">{String(backendRuntime.lastError)}</p>}
        <div className="formActions">
          <button className="button primary" disabled={backendControlsDisabled} onClick={onStartBackend}><PlayCircle size={15} /> Start bundled backend</button>
          <button className="button secondary" disabled={backendControlsDisabled} onClick={onRestartBackend}><RefreshCw size={15} /> Restart backend</button>
          <button className="button secondary" disabled={backendControlsDisabled} onClick={onRefreshBackend}>Refresh status</button>
          <button className="button secondary" disabled={backendControlsDisabled} onClick={onLoadBackendLogs}>Show logs</button>
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
            <button className="button secondary" onClick={() => { setV(''); saveBase(''); }}>Use bundled backend</button>
          </div>
        </details>
      </div>

      <div className="doc pixelPanel providerControlPanel">
        <div className="panelHeader">
          <div>
            <p className="eyebrow">Orchestration provider</p>
            <h2><SlidersHorizontal size={20} /> Provider switchboard</h2>
          </div>
          <span className={`pill ${providerStatus?.status === 'ready' ? 'success' : 'warning'}`}>{providerStatus?.active_provider || 'checking'}</span>
        </div>
        {(providerError || providerSelectError) && <p className="formError">{providerError || providerSelectError}</p>}
        <div className="providerCards">
          {(providerStatus?.providers || []).map(provider => (
            <ProviderCard key={provider.id} provider={provider} busy={providerBusy} onSelect={onSelectProvider} />
          ))}
          {(providerStatus?.providers || []).length === 0 && <p className="subtle">Provider status unavailable.</p>}
        </div>
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
          <div><span>Version</span><b>{codexVersion}</b></div>
          <div><span>Command</span><b>{codexCommand}</b></div>
        </div>
        {codexError && <p className="formError">{codexError}</p>}
        {codexAuth?.message && <p className="subtle">{String(codexAuth.message)}</p>}
        {codexAuth?.login_command && <div className="targetPreview"><b>If a browser did not open, run:</b><code>{String(codexAuth.login_command)}</code></div>}
        <div className="formActions">
          <button className="button primary" disabled={codexBusy || !codexAvailable} onClick={onStartCodexLogin}><BrainCircuit size={15} /> Connect Codex Pro</button>
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
