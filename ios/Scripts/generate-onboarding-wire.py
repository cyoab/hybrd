#!/usr/bin/env python3
"""Generate the onboarding client's Codable wire types from checked-in OpenAPI.

Uses macOS's system Ruby/Psych to read YAML. No network or package installation.
Fails on unsupported schema constructs instead of silently emitting a loose type.
Server validation remains authoritative for numeric bounds and cross-field rules.
"""
import argparse, hashlib, json, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'contracts/openapi.yaml'
OUTPUT = ROOT / 'ios/App/Models/Backend/Generated/BackendWire.swift'
spec = json.loads(subprocess.check_output(['ruby', '-rjson', '-ryaml', '-e',
    'puts JSON.generate(YAML.load_file(ARGV[0]))', str(SOURCE)], text=True))
schemas = spec['components']['schemas']
roots = ['OnboardingState', 'SaveOnboardingDraft', 'CompleteOnboarding',
         'OnboardingDraftSaved', 'StravaConnectionStatus', 'ExerciseCatalog', 'Bootstrap', 'DeviceRegistration', 'RegisteredDevice', 'TrainingPolicy', 'SyncPullResponse', 'SyncPushResponse', 'SyncAcknowledgement', 'ProgressSummary', 'AthleteDetailsInput', 'TrainingPreferencesInput', 'AthleteGoalInput', 'AvailabilityRuleInput', 'AthleteEquipmentInput', 'TrainingBlockInput', 'PlanVersionInput', 'ActivatePlanInput', 'BaselineInput', 'PlanningContextInput', 'AgentRunInput', 'AgentRun', 'AgentCapabilities', 'AgentMemoryInput', 'AgentMemory', 'AgentArtifact']
# Result write variants share the record schema but omit server-owned fields.
record_fields = {'id','createdAt','updatedAt','revision','deletedAt','athleteId'}
for variant in schemas['WorkoutResultRecord']['anyOf']:
    if 'properties' not in variant: continue
    name = 'WorkoutResultInput' + variant['properties']['discipline']['enum'][0].title()
    schemas[name] = {**variant, 'properties': {k:v for k,v in variant['properties'].items() if k not in record_fields}, 'required':[k for k in variant['required'] if k not in record_fields]}
    roots.append(name)
operations = [('getOnboarding', '/v1/onboarding', 'get'),
              ('saveOnboardingDraft', '/v1/onboarding/draft', 'put'),
              ('completeOnboarding', '/v1/onboarding/complete', 'post'),
              ('getStrava', '/v1/integrations/strava', 'get'),
              ('connectStrava', '/v1/integrations/strava/connect', 'post'),
              ('refreshStrava', '/v1/integrations/strava/history', 'post'),
              ('getCatalog', '/v1/catalog', 'get')]
for name, path, method in operations:
    response = spec['paths'][path][method]['responses']
    success = next(v for k,v in response.items() if str(k).startswith('2'))
    schema = success['content']['application/json']['schema']
    if '$ref' not in schema:
        root_name = name[0].upper() + name[1:] + 'Response'
        schemas[root_name] = schema
        roots.append(root_name)

out, queue, emitted, enum_cache = [], list(roots), set(), {}
def upper(s): return s[0].upper() + s[1:]
def ident(s):
    parts = re.findall(r'[a-zA-Z0-9]+', s)
    n = parts[0] + ''.join(upper(x) for x in parts[1:])
    if n[0].isdigit(): n = 'value' + n
    return '`' + n + '`'
def nullable(s):
    if '$ref' in s: return nullable(schemas[s['$ref'].split('/')[-1]])
    return 'null' in (s.get('type') if isinstance(s.get('type'), list) else [s.get('type')]) or any(nullable(v) for v in s.get('anyOf', []) + s.get('allOf', []))
def base_type(s, name):
    if '$ref' in s:
        target = s['$ref'].split('/')[-1]; queue.append(target); return target
    kind = s.get('type')
    if isinstance(kind, list): kind = next(k for k in kind if k != 'null')
    if 'allOf' in s and any('$ref' in x for x in s['allOf']) and all('properties' not in (schemas[x['$ref'].split('/')[-1]] if '$ref' in x else x) for x in s['allOf']):
        return base_type(next(x for x in s['allOf'] if '$ref' in x), name)
    if 'allOf' in s:
        parts = [schemas[x['$ref'].split('/')[-1]] if '$ref' in x else x for x in s['allOf']]
        s = {'type':'object', 'properties':{k:v for x in parts for k,v in x['properties'].items()}, 'required':[k for x in parts for k in x.get('required',[])]}
    if 'anyOf' in s:
        options = [x for x in s['anyOf'] if x.get('type') != 'null']
        if all(x.get('type') == 'number' and len(x.get('enum', [])) == 1 for x in options):
            s = {'type':'integer', 'enum':[x['enum'][0] for x in options]}; kind = 'integer'
        elif all(x.get('type') in ['number','boolean','string'] for x in options): return 'BackendJSONValue'
        elif len(options) == 1: return base_type(options[0], name)
        elif all('properties' in x for x in options):
            schemas[name] = {'oneOf': options}; queue.append(name); return name
        else: raise ValueError(('Unsupported anyOf', name))
    if 'enum' in s:
        values = [x for x in s['enum'] if x is not None]
        if kind == 'boolean':
            if values == [True]: return 'BackendTrue'
            if values == [False]: return 'BackendFalse'
            raise ValueError(('Unsupported boolean literal', name))
        key = json.dumps(values)
        if key not in enum_cache:
            enum_cache[key] = name
            raw = 'String' if kind == 'string' else 'Int'
            cases = []
            for value in values:
                label = ident(value) if isinstance(value,str) else f'value{value}'
                cases.append(f'    case {label} = {json.dumps(value)}')
            out.append(f'  enum {name}: {raw}, Codable, Equatable, Sendable {{\n'+'\n'.join(cases)+'\n  }')
        return enum_cache[key]
    if kind == 'object' and 'properties' not in s:
        if s.get('additionalProperties') == {}: return '[String: BackendJSONValue]'
        return '[String: '+base_type(s['additionalProperties'],name+'Value')+']'
    if kind == 'object' or 'oneOf' in s:
        if name not in schemas: schemas[name] = s
        queue.append(name); return name
    if kind == 'array':
        item = base_type(s['items'], name+'Item')
        if nullable(s['items']): item += '?'
        return '['+item+']'
    if kind == 'string':
        if s.get('format') == 'uuid': return 'UUID'
        if s.get('format') == 'date': return 'BackendDay'
        if s.get('format') == 'date-time': return 'BackendInstant'
        if s.get('pattern') == '^(0|[1-9][0-9]*)$': return 'BackendRevision'
        return 'String'
    if kind == 'null': return 'BackendNull'
    if kind in ['integer','number','boolean']: return {'integer':'Int','number':'Double','boolean':'Bool'}[kind]
    raise ValueError(('Unsupported schema', name, s))

def emit(name):
    if name in emitted: return
    emitted.add(name); s = schemas[name]
    if 'allOf' in s:
        parts = [schemas[x['$ref'].split('/')[-1]] if '$ref' in x else x for x in s['allOf']]
        s = {'type':'object', 'properties':{k:v for x in parts for k,v in x['properties'].items()}, 'required':[k for x in parts for k in x.get('required',[])]}
    if 'anyOf' in s:
        options = [x for x in s['anyOf'] if x.get('type') != 'null']
        s = options[0] if len(options) == 1 else {'oneOf': options}
    if 'oneOf' in s:
        variants = []
        discriminator_key = next(k for k in ['source','entityType','discipline','kind','type','decisionType'] if all(k in v.get('properties',{}) and len(v['properties'][k].get('enum',[]))==1 for v in s['oneOf']))
        for v in s['oneOf']:
            discriminator = v['properties'][discriminator_key]['enum'][0]
            variants.append((discriminator, base_type(v, name+upper(ident(discriminator).strip('`')))))
        lines = [f'  enum {name}: Codable, Equatable, Sendable {{']
        lines += [f'    case {ident(key)}({typ})' for key,typ in variants]
        lines += [f'    private enum CodingKeys: String, CodingKey {{ case {discriminator_key} }}',
                  '    init(from decoder: Decoder) throws {',
                  '      let c = try decoder.container(keyedBy: CodingKeys.self)',
                  f'      switch try c.decode(String.self, forKey: .{discriminator_key}) {{']
        lines += [f'      case "{key}": self = .{ident(key)}(try {typ}(from: decoder))' for key,typ in variants]
        lines += [f'      default: throw DecodingError.dataCorruptedError(forKey: .{discriminator_key}, in: c, debugDescription: "Unsupported discriminator")','      }','    }',
                  '    func encode(to encoder: Encoder) throws {','      switch self {']
        lines += [f'      case .{ident(key)}(let value): try value.encode(to: encoder)' for key,_ in variants]
        lines += ['      }','    }','  }']; out.append('\n'.join(lines)); return
    if 'properties' not in s:
        out.append(f'  typealias {name} = {base_type(s,name)}'); return
    fields=[]
    for key, value in s['properties'].items():
        typ=base_type(value,name+upper(key)); required=key in s.get('required',[])
        null=nullable(value)
        # OpenAPI shares a nullable draft component with GET. A save always requires a draft.
        if name == 'SaveOnboardingDraft' and key == 'draft': null=False
        fields.append((key,typ,required,null))
    lines=[f'  struct {name}: Codable, Equatable, Sendable {{']
    lines += [f'    var {ident(k)}: {t}{"?" if n or not r else ""}' for k,t,r,n in fields]
    params=[f'{ident(k)}: {t}{"? = nil" if n or not r else ""}' for k,t,r,n in fields]
    lines += ['    init('+', '.join(params)+') {']
    lines += [f'      self.{ident(k)} = {ident(k)}' for k,_,_,_ in fields]
    lines += ['    }','    private enum CodingKeys: String, CodingKey {']
    lines += [f'      case {ident(k)} = {json.dumps(k)}' for k,_,_,_ in fields]
    lines += ['    }','    init(from decoder: Decoder) throws {','      let c = try decoder.container(keyedBy: CodingKeys.self)']
    lines += [f'      {ident(k)} = try c.{"decode" if r else "decodeIfPresent"}({t}{"?" if n and r else ""}.self, forKey: .{ident(k)})' for k,t,r,n in fields]
    lines += ['    }','    func encode(to encoder: Encoder) throws {','      var c = encoder.container(keyedBy: CodingKeys.self)']
    for k,t,r,n in fields:
        value = ident(k)
        if t == 'UUID': value += ('?' if n or not r else '') + '.uuidString.lowercased()'
        elif t == '[UUID]': value += ('?' if n or not r else '') + '.map { $0.uuidString.lowercased() }'
        lines.append(f'      try c.{"encode" if r or n else "encodeIfPresent"}({value}, forKey: .{ident(k)})')
    lines += ['    }','  }']; out.append('\n'.join(lines))

while queue: emit(queue.pop(0))
header = '// Generated by Scripts/generate-onboarding-wire.py. Do not edit.\n'
header += '// OpenAPI SHA256: '+hashlib.sha256(SOURCE.read_bytes()).hexdigest()+'\n'
header += '// Nullable required fields encode as null. Dates/revisions remain lossless.\nimport Foundation\n\nenum BackendWire {\n'
result=header+'\n\n'.join(out)+'\n}\n\nenum OnboardingEndpoint: String, Codable, Sendable {\n'
result+='\n'.join('  case '+name for name,_,_ in operations)+'\n  var path: String {\n    switch self {\n'
result+='\n'.join(f'    case .{name}: "{path}"' for name,path,_ in operations)+'\n    }\n  }\n  var method: String {\n    switch self {\n'
result+='\n'.join(f'    case .{name}: "{method.upper()}"' for name,_,method in operations)+'\n    }\n  }\n}\n'
parser=argparse.ArgumentParser(); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
if args.check:
    if not OUTPUT.exists() or OUTPUT.read_text()!=result: raise SystemExit('Onboarding wire types are stale; regenerate them.')
    print('Onboarding wire types match OpenAPI.')
else:
    OUTPUT.parent.mkdir(parents=True,exist_ok=True); OUTPUT.write_text(result)
    print(f'Generated {len(emitted)} wire types from OpenAPI.')
