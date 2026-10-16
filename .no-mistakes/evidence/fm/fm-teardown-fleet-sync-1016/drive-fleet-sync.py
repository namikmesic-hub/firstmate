import json, os, pathlib, shutil, subprocess, sys
ROOT = pathlib.Path('/Users/namikmesic/.no-mistakes/worktrees/5435c2ef752e/01M525K1EG77S2Q27ED04E5Y0C')
EVIDENCE = pathlib.Path('/Users/namikmesic/.no-mistakes/evidence/01M525K1EG77S2Q27ED04E5Y0C')
AREA = ROOT / '.live-fleet-sync'
SOCKET = ROOT / '.fmsock'
AREA.mkdir(exist_ok=True)
(AREA / 'tmp').mkdir(exist_ok=True)
env = {k: v for k,v in os.environ.items() if not k.startswith(('FM_', 'TASKS_AXI_', 'GIT_')) and k not in ('TMUX','TMUX_PANE','HERDR_SESSION','HERDR_ENV')}
env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='Lab tester', GIT_AUTHOR_EMAIL='lab@example.invalid', GIT_COMMITTER_NAME='Lab tester', GIT_COMMITTER_EMAIL='lab@example.invalid', TMPDIR=str(AREA/'tmp'), TMUX=f'{SOCKET},0,0')
log = None

def run(args, cwd=ROOT, check=True, scenario_env=None):
    args = [str(a) for a in args]
    p = subprocess.run(args, cwd=cwd, env=scenario_env or env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        log.write('$ ' + ' '.join(args) + '\n' + p.stdout + f'[exit {p.returncode}]\n')
        log.flush()
    if check and p.returncode:
        raise RuntimeError(f'{args}: exit {p.returncode}\n{p.stdout}')
    return p

def git(path, *args, **kw): return run(['git','-C',path,*args], **kw).stdout.strip()

def scenario(name):
    global log
    log = open(EVIDENCE/f'{name}.log','w')
    home = AREA/name
    run([ROOT/'bin/fm-lab-home.sh','create',home])
    senv = dict(env, FM_HOME=str(home))
    project=home/'projects/demo'
    origin=home/'origin.git'
    seed=home/'seed'
    run(['git','init','--bare','--initial-branch=main',origin])
    run(['git','clone',origin,seed])
    (seed/'readme.txt').write_text('baseline\n')
    (seed/'.gitignore').write_text('/.treehouse\n')
    (seed/'treehouse.toml').write_text('max_trees = 2\nroot = "./"\n')
    git(seed,'add','.')
    git(seed,'commit','-m','Baseline')
    git(seed,'push','origin','main')
    run(['git','clone',origin,project])
    mode='local-only' if name=='local-only' else 'no-mistakes'
    (home/'data/projects.md').write_text(f'# Projects\n\n- demo: isolated test project; {mode}\n')
    # Acquire an actual reusable pool slot through Treehouse's public interface.
    wt=pathlib.Path(run(['treehouse','get','--lease','--lease-holder','lab-fleet-sync'],cwd=project,scenario_env=senv).stdout.strip().splitlines()[-1])
    assert wt.is_relative_to(ROOT), wt
    git(wt,'switch','-c','fm/lab-scout')
    assert not git(project,'status','--porcelain'), 'project must start clean'
    (seed/'remote.txt').write_text('merged upstream\n')
    git(seed,'add','remote.txt')
    git(seed,'commit','-m','Upstream merge')
    git(seed,'push','origin','main')
    git(project,'fetch','origin')
    git(wt,'reset','--hard','origin/main')
    before=git(project,'rev-parse','main')
    remote=git(origin,'rev-parse','main')
    assert before != remote
    task='lab-scout'
    kind='ship' if name=='ship-refresh' else 'scout'
    (home/'data'/task).mkdir()
    (home/'data'/task/'report.md').write_text('Lab scout completed. No unresolved decisions.\n')
    (home/'data/backlog.md').write_text('# Backlog\n\n## In flight\n\n## Queued\n\n## Done\n')
    run(['tasks-axi','add',task,'Lab scout','--kind',kind,'--file',home/'data/backlog.md'],scenario_env=senv)
    run(['tasks-axi','start',task,'--file',home/'data/backlog.md'],scenario_env=senv)
    (home/'state'/f'{task}.meta').write_text(f'window=fm-lab-fleet:fm-{task}\nendpoint_task_id={task}\nbackend=tmux\nworktree={wt}\nproject={project}\nkind={kind}\nmode={mode}\nspawn_gen=live-{name}\n')
    if kind=='scout': run([ROOT/'bin/fm-captain-hold.sh','complete',task,'--none'],scenario_env=senv)
    run(['tmux','-S',SOCKET,'new-window','-d','-t','fm-lab-fleet','-n',f'fm-{task}','-c',wt,'/bin/sh'])
    run(['tmux','-S',SOCKET,'list-windows','-t','fm-lab-fleet','-F','#{window_name} #{pane_current_path}'])
    log.write(f'BEFORE main={before}\norigin/main={remote}\nworker_HEAD={git(wt,"rev-parse","HEAD")}\n')
    if name=='dirty': (project/'readme.txt').write_text('local uncommitted work\n')
    if name=='diverged':
        (project/'private.txt').write_text('unpublished commit\n')
        git(project,'add','private.txt'); git(project,'commit','-m','Private local work')
        before=git(project,'rev-parse','main')
    if name=='other-branch': git(project,'switch','-c','private-branch')
    if name=='no-origin': git(project,'remote','remove','origin')
    if name=='fetch-failure': git(project,'remote','set-url','origin',home/'missing.git')
    if name=='missing-report': (home/'data'/task/'report.md').unlink()
    dry=run([ROOT/'bin/fm-remote-job-reap-orphans.sh','--dry-run'])
    assert not dry.stdout.strip(), 'Unsafe external orphan sweep candidates'
    p=run([ROOT/'bin/fm-teardown.sh',task],scenario_env=senv,check=False)
    after=git(project,'rev-parse','main')
    log.write(f'AFTER main={after}\nExpected remote={remote}\n')
    windows=run(['tmux','-S',SOCKET,'list-windows','-t','fm-lab-fleet','-F','#{window_name}']).stdout
    status=run(['treehouse','status'],cwd=project,scenario_env=senv).stdout
    run(['tasks-axi','show',task,'--file',home/'data/backlog.md'],scenario_env=senv)
    if name=='missing-report':
        assert p.returncode != 0 and before==after
        assert (home/'state'/f'{task}.meta').exists()
        assert f'fm-{task}' in windows
        # Complete the previously missing deliverable, then clean up normally.
        (home/'data'/task/'report.md').write_text('Lab scout completed. No unresolved decisions.\n')
        run([ROOT/'bin/fm-teardown.sh',task],scenario_env=senv)
    else:
        assert p.returncode==0, p.stdout
        assert not (home/'state'/f'{task}.meta').exists()
        assert f'fm-{task}' not in windows
        assert (home/'data'/task/'report.md').exists()
        if name in ('scout-refresh','ship-refresh'):
            assert after==remote
            assert git(wt,'rev-parse','main')==remote
            log.write('Shared pool main now equals origin/main.\n')
        else: assert before==after
        if name in ('dirty','diverged','other-branch'): assert 'STUCK:' in p.stdout
        if name=='dirty': assert (project/'readme.txt').read_text()=='local uncommitted work\n'
        if name=='diverged': assert (project/'private.txt').read_text()=='unpublished commit\n'
        if name=='other-branch': assert git(project,'branch','--show-current')=='private-branch'
        if name=='no-origin': assert 'no origin remote' in p.stdout
        if name=='fetch-failure': assert 'fetch failed' in p.stdout
    log.write('Scenario observations satisfied.\n'); log.close(); log=None
    shutil.rmtree(home)
    return {'name':name,'result':'pass','live':True,'evidence':str(EVIDENCE/f'{name}.log'),'reason':''}

results=json.loads((EVIDENCE/'live-results.json').read_text()) if (EVIDENCE/'live-results.json').exists() else []
try:
    run(['tmux','-f','/dev/null','-S',SOCKET,'new-session','-d','-s','fm-lab-fleet','-n','keeper','-c',ROOT,'/bin/sh'])
    for name in sys.argv[1:] or ['scout-refresh']:
        try:
            result=scenario(name); results.append(result); print(json.dumps(result),flush=True)
        except Exception as e:
            results.append({'name':name,'result':'fail','error':str(e)})
            print(json.dumps(results[-1]),flush=True)
            raise
finally:
    if log: log.close(); log=None
    run(['tmux','-S',SOCKET,'kill-server'],check=False)
    if SOCKET.exists(): SOCKET.unlink()
    (EVIDENCE/'live-results.json').write_text(json.dumps(results,indent=2)+'\n')
