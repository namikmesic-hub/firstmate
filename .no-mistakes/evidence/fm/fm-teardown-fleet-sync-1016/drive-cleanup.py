from pathlib import Path
import os, subprocess, tempfile, shutil, json, shlex, sys

ROOT = Path.cwd()
EVIDENCE = Path('/Users/namikmesic/.no-mistakes/evidence/01M6CRCEPN9WG3X4ARY7F3SCTD')
SCRATCH = Path(tempfile.mkdtemp(prefix='.cleanup-live-', dir=ROOT))
ENV = dict(os.environ)
for k in list(ENV):
    if k.startswith(('FM_', 'HERDR_', 'TASKS_AXI_')) or k in ('TMUX', 'TMUX_PANE', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
        ENV.pop(k)
ENV.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='Lab', GIT_AUTHOR_EMAIL='lab@example.invalid', GIT_COMMITTER_NAME='Lab', GIT_COMMITTER_EMAIL='lab@example.invalid', FM_HERDR_LAB_STATE_DIR=str(SCRATCH/'herdr-lab-state'))
ORIGINAL_PATH = ENV['PATH']
HELPER = str(ROOT/'bin/fm-herdr-lab.sh')
TRANSCRIPT = None
RESULTS = []
SESSION = None
PROVISIONED = False

def log(s):
    if TRANSCRIPT and not TRANSCRIPT.closed:
        TRANSCRIPT.write(s+'\n'); TRANSCRIPT.flush()

def run(args, cwd=ROOT, env=None, ok=True, timeout=90):
    args = [str(a) for a in args]
    log('$ '+shlex.join(args))
    r = subprocess.run(args, cwd=cwd, env=env or ENV, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    log(r.stdout.rstrip())
    if r.stderr: log('stderr:\n'+r.stderr.rstrip())
    log('exit='+str(r.returncode))
    if ok and r.returncode:
        raise RuntimeError(f'{shlex.join(args)} returned {r.returncode}: {r.stderr}')
    return r

def git(p, *args): return run(['git','-C',p,*args]).stdout.strip()
def lab(*args, ok=True): return run([HELPER,'run',SESSION,*args], env=ENV,ok=ok)
def assert_eq(a,b,label):
    log(f'{label}: actual={a!r}, expected={b!r}')
    if a!=b: raise AssertionError(label)

def case(name, kind='scout', mode='no-mistakes', registry='no-mistakes', state='safe', refresh=True):
    global TRANSCRIPT
    with (EVIDENCE/(name+'.log')).open('w') as f:
        TRANSCRIPT=f
        log('Scenario: '+name+'\nReal fm-teardown, Git, Treehouse, and named Herdr lab. No service stubs.\nSession: '+SESSION)
        home=SCRATCH/name
        run([ROOT/'bin/fm-lab-home.sh','create',home])
        env=dict(ENV, FM_HOME=str(home), HERDR_SESSION=SESSION)
        fakebin=SCRATCH/'transport'
        env['PATH']=str(fakebin)+':'+ORIGINAL_PATH
        origin=home/'origin.git'; seed=home/'seed'; proj=home/'projects/demo'
        run(['git','init','-q','--bare','--initial-branch=main',origin])
        run(['git','clone','-q',origin,seed])
        (seed/'readme.txt').write_text('baseline\n')
        (seed/'treehouse.toml').write_text('max_trees = 3\nroot = "./"\n')
        (seed/'.gitignore').write_text('.treehouse/\n')
        git(seed,'add','.'); git(seed,'commit','-qm','baseline'); git(seed,'push','-q','origin','main')
        run(['git','clone','-q',origin,proj])
        (home/'data/projects.md').write_text(f'- demo [{registry}] - Live test clone\n')
        (home/'config/herdr-presentation-spaces').write_text('off\n')
        (home/'state/.last-watcher-beat').touch()
        before=git(proj,'rev-parse','main')
        (seed/'upstream.txt').write_text('landed upstream\n'); git(seed,'add','.'); git(seed,'commit','-qm','upstream advance'); git(seed,'push','-q','origin','main')
        remote=git(origin,'rev-parse','main')
        assert before != remote
        git(proj,'fetch','-q','origin')
        lease=json.loads(run(['treehouse','get','--lease','--json','--lease-holder',name],cwd=proj).stdout)
        log('Treehouse lease='+json.dumps(lease))
        # Treehouse adds its own ignore entry. Restore the known fixture file so clean-clone checks start clean.
        git(proj,'diff','--','.gitignore')
        git(proj,'restore','--','.gitignore')
        wt=Path(lease.get('path') or lease.get('worktree_path') or lease.get('worktree',{}).get('path',''))
        if not wt.is_absolute() or not wt.is_dir(): raise RuntimeError('Cannot resolve Treehouse lease path')
        git(wt,'checkout','-qb','fm/'+name,'origin/main')
        spectator=None
        if name=='scout-refresh':
            spectator=home/'observer'
            git(proj,'worktree','add','-qb','observer',spectator,'origin/main')
            log('Observer common Git directory: '+git(spectator,'rev-parse','--git-common-dir'))
            assert_eq(git(spectator,'rev-parse','main'),before,'observer sees stale clone main before cleanup')
            observer_head=git(spectator,'rev-parse','HEAD')
        if state=='dirty': (proj/'readme.txt').write_text('operator edit\n')
        if state=='feature': git(proj,'checkout','-qb','operator-work')
        if state=='diverged':
            (proj/'local.txt').write_text('local work\n'); git(proj,'add','.'); git(proj,'commit','-qm','operator local commit')
        if state=='detached-unique':
            git(proj,'checkout','--detach','-q')
            (proj/'local.txt').write_text('detached work\n'); git(proj,'add','.'); git(proj,'commit','-qm','unique detached commit')
        if state=='default-elsewhere':
            git(proj,'checkout','--detach','-q')
            git(proj,'worktree','add','-q',home/'operator-main','main')
        if state=='no-origin': git(proj,'remote','remove','origin')
        if state=='fetch-failure': git(proj,'remote','set-url','origin',home/'unavailable.git')
        initial_head=git(proj,'rev-parse','HEAD')
        initial_main=git(proj,'rev-parse','main')
        initial_status=git(proj,'status','--porcelain')
        initial_branch=git(proj,'symbolic-ref','--quiet','--short','HEAD') if state not in ('detached-unique','default-elsewhere') else ''
        id='task-'+name
        if kind=='secondmate':
            sub=SCRATCH/(name+'-secondmate-home')
            for d in ('state','data','config','projects'): (sub/d).mkdir(parents=True, exist_ok=True)
            (sub/'.fm-secondmate-home').write_text(id+'\n')
            workdir=sub
        else: workdir=wt
        created=json.loads(lab('workspace','create','--cwd',str(workdir),'--label','fm-'+id,'--no-focus').stdout)['result']
        ws=created['workspace']['workspace_id']; pane=created['root_pane']['pane_id']; tab=created['tab']['tab_id']
        meta={'window':SESSION+':'+pane,'endpoint_task_id':id,'worktree':str(wt),'project':str(proj),'kind':kind,'mode':mode,'spawn_gen':'live-'+name,'backend':'herdr','herdr_session':SESSION,'herdr_workspace_id':ws,'herdr_tab_id':tab,'herdr_pane_id':pane,'decisions_reviewed':'1'}
        if kind=='secondmate':
            meta['home']=str(sub)
            meta['worktree']=str(sub)
        (home/'state'/f'{id}.meta').write_text(''.join(k+'='+v+'\n' for k,v in meta.items()))
        if kind=='scout':
            (home/'data'/id).mkdir(); (home/'data'/id/'report.md').write_text('Lab scout report. No open decisions.\n')
        runtime=ROOT
        if kind=='secondmate':
            # The supported FM_HOME layout can be separate from installed code.
            # Retirement refuses a home inside its code root, so copy the unchanged runtime within this worktree.
            runtime=SCRATCH/'installed-runtime'
            shutil.copytree(ROOT/'bin',runtime/'bin')
            log('Secondmate scenario uses the unchanged bin runtime copied to '+str(runtime))
        cmd=[runtime/'bin/fm-teardown.sh',id]
        if kind=='secondmate': cmd.append('--force')
        r=run(cmd,env=env,ok=False)
        assert_eq(r.returncode,0,'cleanup exit status')
        assert_eq((home/'state'/f'{id}.meta').exists(),False,'task metadata retired')
        assert_eq(lab('pane','get',pane,ok=False).returncode,1,'recorded task pane closed')
        if refresh:
            assert_eq(git(proj,'rev-parse','main'),remote,'clone main equals upstream after cleanup')
            assert_eq(git(proj,'status','--porcelain'),'','clone remains clean')
        else:
            assert_eq(git(proj,'rev-parse','main'),initial_main,'clone main unchanged')
            assert_eq(git(proj,'rev-parse','HEAD'),initial_head,'clone HEAD unchanged')
            assert_eq(git(proj,'status','--porcelain'),initial_status,'operator working files unchanged')
            if initial_branch: assert_eq(git(proj,'symbolic-ref','--short','HEAD'),initial_branch,'checked-out branch unchanged')
        if state in ('dirty','feature','diverged','detached-unique','default-elsewhere'):
            assert 'STUCK:' in r.stdout, 'missing unsafe-state warning'
        if state=='no-origin': assert 'skipped: no origin remote' in r.stdout
        if state=='fetch-failure': assert 'skipped: fetch failed' in r.stdout
        if spectator:
            assert_eq(git(spectator,'rev-parse','main'),remote,'remaining pool worker sees updated main')
            assert_eq(git(spectator,'rev-parse','HEAD'),observer_head,'remaining pool worker HEAD preserved')
            assert_eq(git(spectator,'rev-list','--count','main..HEAD'),'0','remaining pool worker matches main')
        if kind=='secondmate': assert_eq(sub.exists(),False,'disposable secondmate home retired')
        else:
            assert_eq(git(wt,'status','--porcelain'),'','returned pool slot is clean')
            run(['treehouse','status'],cwd=proj)
        log('RESULT: PASS')
        RESULTS.append({'name':name,'result':'pass','live':True,'evidence':str(EVIDENCE/(name+'.log')),'reason':''})
        print(name+': PASS',flush=True)
    TRANSCRIPT=None

try:
    with (EVIDENCE/'lab-lifecycle.log').open('a') as f:
        TRANSCRIPT=f
        SESSION=run([HELPER,'name','cleanup-refresh']).stdout.strip()
        # provision calls prepare itself for a fresh session and records the default-session tripwire.
        run([HELPER,'provision',SESSION]); PROVISIONED=True
        run([HELPER,'run',SESSION,'status','--json'])
    TRANSCRIPT=None
    transport=SCRATCH/'transport'; transport.mkdir()
    wrapper=transport/'herdr'
    wrapper.write_text('''#!/usr/bin/env python3
import os,sys
args=sys.argv[1:]
session=os.environ['HERDR_LAB_SESSION']
if len(args)>=2 and args[-2:]==['--session',session]: args=args[:-2]
if any(a=='--session' or a.startswith('--session=') for a in args): sys.exit(9)
e=dict(os.environ,PATH=os.environ['HERDR_ORIGINAL_PATH'])
if args==['--version']:
 os.execvpe('herdr',['herdr','--version','--session',session],e)
os.execve(os.environ['HERDR_LAB_HELPER'],[os.environ['HERDR_LAB_HELPER'],'run',session]+args,e)
'''); wrapper.chmod(0o755)
    ENV.update(HERDR_LAB_SESSION=SESSION,HERDR_LAB_HELPER=HELPER,HERDR_ORIGINAL_PATH=ORIGINAL_PATH)
    cases=[
        ('scout-refresh',{}),
        ('ship-refresh',dict(kind='ship',mode='direct-PR')),
        ('local-only-scout',dict(registry='local-only',refresh=False)),
        ('local-only-task',dict(mode='local-only',refresh=False)),
        ('secondmate-exclusion',dict(kind='secondmate',mode='secondmate',refresh=False)),
        ('dirty-clone',dict(state='dirty',refresh=False)),
        ('feature-clone',dict(state='feature',refresh=False)),
        ('diverged-clone',dict(state='diverged',refresh=False)),
        ('detached-unique',dict(state='detached-unique',refresh=False)),
        ('default-elsewhere',dict(state='default-elsewhere',refresh=False)),
        ('no-origin',dict(state='no-origin',refresh=False)),
        ('fetch-failure',dict(state='fetch-failure',refresh=False)),
    ]
    for name, opts in cases:
        if any(r['name']==name and r['result']=='pass' for r in RESULTS): continue
        try: case(name,**opts)
        except Exception as exc:
            log('RESULT: ERROR '+str(exc)); print(name+': ERROR '+str(exc),flush=True)
            RESULTS.append({'name':name,'result':'fail','live':True,'evidence':str(EVIDENCE/(name+'.log')),'reason':str(exc)})
            raise
finally:
    TRANSCRIPT=None
    with (EVIDENCE/'lab-lifecycle.log').open('a') as f:
        TRANSCRIPT=f
        if PROVISIONED:
            run([HELPER,'teardown',SESSION],ok=True)
            log('Named lab removed; default-session tripwire unchanged.')
    TRANSCRIPT=None
    (EVIDENCE/'live-results.json').write_text(json.dumps(RESULTS,indent=2)+'\n')
    shutil.rmtree(SCRATCH)
    print('Disposable fixture files removed.',flush=True)
