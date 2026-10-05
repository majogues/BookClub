const COLORS = ['#b7a7e8','#9dbda7','#e9a6a6','#92bed6','#e9cf84','#d59c7d'];
const $ = (s) => document.querySelector(s);
const cfg = window.APP_CONFIG || {};
const configured = cfg.SUPABASE_URL && cfg.SUPABASE_PUBLISHABLE_KEY && !cfg.SUPABASE_URL.startsWith('PASTE_') && !cfg.SUPABASE_PUBLISHABLE_KEY.startsWith('PASTE_');
let client=null, sessionToken=null, me=null, state=null, rotation=0, busy=false, pendingAction=null, pollTimer=null, selectedProfile='Majo', profileNeedsSetup=null;
if(configured){client=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false}})}else{$('#authError').textContent='Falta conectar Supabase en config.js.';$('#loginBtn').disabled=true}
function escapeHtml(s=''){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]))}
function when(ts){return new Date(ts).toLocaleString('es-ES',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'})}
function currentMember(){return state?.members.find(m=>m.player_id===state.club.current_turn_player)}
function memberName(id){return state?.members.find(m=>m.player_id===id)?.display_name||'Alguien'}
function myJokers(){return state?.jokers.find(j=>j.player_id===state.club.current_turn_player)||{nope_used:true,why_used:true,decide_used:true}}
function availablePrompts(){if(!state)return[];const used=new Set(state.clubPrompts.filter(x=>x.used).map(x=>x.prompt_id));return state.prompts.filter(p=>!used.has(p.id))}
function isMyTurn(){return !!(me&&state&&state.club.current_turn_player===me.player_id)}
function modal(title,text,fn){$('#modalTitle').textContent=title;$('#modalText').textContent=text;$('#confirmModal').classList.add('show');pendingAction=fn}
function closeModal(){$('#confirmModal').classList.remove('show');pendingAction=null}
$('#cancelModal').onclick=closeModal;$('#confirmAction').onclick=async()=>{const fn=pendingAction;closeModal();if(fn)await fn()}
function showAuth(show=true){$('#authScreen').classList.toggle('hidden',!show)}
function setOffline(flag){$('#offlineBanner').classList.toggle('show',flag)}
function fail(err){console.error(err);alert(err?.message||String(err||'Ocurrió un error.'))}
async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw error;return data}
async function refreshAuthMode(){
  if(!client)return;
  $('#authError').textContent='';
  $('#loginBtn').disabled=true;
  $('#authPin').value='';
  $('#authPinConfirm').value='';
  try{
    const d=await rpc('profile_status',{p_name:selectedProfile});
    profileNeedsSetup=!d.pin_initialized;
    $('#authPinConfirm').style.display=profileNeedsSetup?'block':'none';
    $('#loginBtn').textContent=profileNeedsSetup?'Crear mi PIN':'Entrar';
    $('#authModeNote').textContent=profileNeedsSetup
      ? `Primer acceso de ${d.display_name}: crea un PIN privado. Se guardará de forma segura y solo podrás configurarlo esta vez.`
      : `${d.display_name} ya configuró su PIN. Introdúcelo para entrar.`;
    $('#authPin').setAttribute('autocomplete',profileNeedsSetup?'new-password':'current-password');
  }catch(e){
    console.error(e);
    profileNeedsSetup=null;
    $('#authModeNote').textContent='No pude comprobar este perfil.';
    $('#authError').textContent=e?.message||'Perfil no disponible.';
  }finally{
    $('#loginBtn').disabled=false;
  }
}

document.querySelectorAll('.profile-btn').forEach(btn=>btn.onclick=async()=>{
  document.querySelectorAll('.profile-btn').forEach(b=>b.classList.remove('selected'));
  btn.classList.add('selected');
  selectedProfile=btn.dataset.name;
  await refreshAuthMode();
  $('#authPin').focus();
});

async function login(){
  if(!client)return;
  const pin=$('#authPin').value.trim();
  const confirm=$('#authPinConfirm').value.trim();
  $('#authError').textContent='';
  if(!pin){$('#authError').textContent='Escribe tu PIN.';return}
  if(profileNeedsSetup){
    if(pin.length<6){$('#authError').textContent='El PIN debe tener al menos 6 caracteres.';return}
    if(pin!==confirm){$('#authError').textContent='Los dos PIN no coinciden.';return}
  }
  $('#loginBtn').disabled=true;
  try{
    const d=profileNeedsSetup
      ? await rpc('initialize_player_pin',{p_name:selectedProfile,p_pin:pin})
      : await rpc('login_player',{p_name:selectedProfile,p_pin:pin});
    sessionToken=d.session;
    me={player_id:d.player_id,display_name:d.display_name,club_id:d.club_id};
    localStorage.setItem('entre_paginas_session',sessionToken);
    $('#authPin').value='';
    $('#authPinConfirm').value='';
    await enterApp();
  }catch(e){
    console.error(e);
    $('#authError').textContent=profileNeedsSetup
      ? (e?.message||'No pude crear el PIN.')
      : 'PIN incorrecto.';
    if(profileNeedsSetup) await refreshAuthMode();
  }finally{$('#loginBtn').disabled=false}
}
$('#loginBtn').onclick=login;
$('#authPin').addEventListener('keydown',e=>{if(e.key==='Enter'&&!profileNeedsSetup)login()});
$('#authPinConfirm').addEventListener('keydown',e=>{if(e.key==='Enter'&&profileNeedsSetup)login()});
$('#logoutBtn').onclick=async()=>{if(pollTimer)clearInterval(pollTimer);try{if(sessionToken)await rpc('logout_player',{p_session:sessionToken})}catch{}localStorage.removeItem('entre_paginas_session');sessionToken=null;me=null;state=null;showAuth(true)};
async function enterApp(){$('#viewerName').textContent=`Entraste como ${me.display_name}`;showAuth(false);await loadState(true);if(pollTimer)clearInterval(pollTimer);pollTimer=setInterval(()=>{if(!busy)loadState(false)},5000)}
async function loadState(showErrors=false){if(!client||!sessionToken)return;try{state=await rpc('read_club_state',{p_session:sessionToken});me=state.me;setOffline(false);render()}catch(e){setOffline(true);if(showErrors)fail(e)}}
function drawWheel(){const svg=$('#wheel'),items=availablePrompts();svg.innerHTML='';if(!items.length){svg.innerHTML='<circle cx="300" cy="300" r="285" fill="#ece7df"/><text x="300" y="300" text-anchor="middle" dominant-baseline="middle" font-family="DM Serif Display" font-size="36" fill="#777986">Fin de temporada</text>';return}const n=items.length,cx=300,cy=300,r=285;items.forEach((p,i)=>{const a0=(i/n)*Math.PI*2-Math.PI/2,a1=((i+1)/n)*Math.PI*2-Math.PI/2,x0=cx+r*Math.cos(a0),y0=cy+r*Math.sin(a0),x1=cx+r*Math.cos(a1),y1=cy+r*Math.sin(a1);const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',`M ${cx} ${cy} L ${x0} ${y0} A ${r} ${r} 0 ${a1-a0>Math.PI?1:0} 1 ${x1} ${y1} Z`);path.setAttribute('fill',COLORS[i%COLORS.length]);path.setAttribute('stroke','#fffdf9');path.setAttribute('stroke-width','3');svg.appendChild(path);const mid=(a0+a1)/2,tr=240,tx=cx+tr*Math.cos(mid),ty=cy+tr*Math.sin(mid),text=document.createElementNS('http://www.w3.org/2000/svg','text');text.setAttribute('x',tx);text.setAttribute('y',ty);text.setAttribute('text-anchor','middle');text.setAttribute('dominant-baseline','middle');text.setAttribute('font-family','DM Sans');text.setAttribute('font-weight','700');text.setAttribute('font-size',n>20?'14':'18');text.setAttribute('fill','#20212a');text.textContent=p.id;svg.appendChild(text)});const c=document.createElementNS('http://www.w3.org/2000/svg','circle');c.setAttribute('cx',300);c.setAttribute('cy',300);c.setAttribute('r',98);c.setAttribute('fill','#fffdf9');svg.appendChild(c)}
function formatEvent(e){const who=e.actor?memberName(e.actor):'',d=e.detail||{},p=id=>state.prompts.find(x=>x.id===Number(id));switch(e.event_type){case'season_started':return`Temporada iniciada. ${d.first_turn||'Primer turno'} empieza.`;case'spin':{const x=p(d.prompt_id);return`${who} giró la ruleta → #${d.prompt_id}${x?' '+x.title:''}.`}case'nope':{const x=p(d.discarded_prompt_id);return`${who} usó NOPE y descartó #${d.discarded_prompt_id}${x?' '+x.title:''}.`}case'spin_after_nope':{const x=p(d.prompt_id);return`Nuevo giro → #${d.prompt_id}${x?' '+x.title:''}.`}case'why':return`${who} usó PORQUE QUIERO.`;case'decide':return`${who} usó TÚ DECIDES. El turno pasó a ${memberName(d.new_turn)}.`;case'book_saved':return`${who} guardó “${d.title}” — ${d.author}.`;default:return`${who?who+' · ':''}${e.event_type}`}}
function renderHistory(){$('#historyList').innerHTML=(state?.events||[]).map(e=>`<div class="event"><time>${escapeHtml(when(e.created_at))}</time><p>${escapeHtml(formatEvent(e))}</p></div>`).join('')||'<div class="event"><p>Aún no hay acciones.</p></div>'}
function render(){if(!state)return;drawWheel();const turn=currentMember(),mine=isMyTurn(),j=myJokers(),pending=!!state.club.pending_mode,canEditBook=mine&&pending&&!busy,currentPrompt=state.prompts.find(p=>p.id===state.club.pending_prompt);$('#turnName').textContent=turn?.display_name||'—';$('#jokerOwner').textContent='de '+(turn?.display_name||'—');$('#roundLabel').textContent='Ronda '+state.club.round;$('#remainingLabel').textContent=`${availablePrompts().length} prompts disponibles`;$('#turnStatus').textContent=pending?(mine?'debe guardar el libro':`esperando a ${turn?.display_name||'la otra persona'}`):(mine?'lista para elegir':`esperando a ${turn?.display_name||'la otra persona'}`);$('#nopeState').textContent=j.nope_used?'USADO':'1×';$('#whyState').textContent=j.why_used?'USADO':'1×';$('#decideState').textContent=j.decide_used?'USADO':'1×';$('#nopeBtn').disabled=busy||!mine||j.nope_used||state.club.pending_mode!=='spin';$('#whyBtn').disabled=busy||!mine||j.why_used||pending;$('#decideBtn').disabled=busy||!mine||j.decide_used||pending;$('#spinBtn').disabled=busy||!mine||pending||availablePrompts().length===0;$('#bookBox').classList.toggle('locked',!canEditBook);$('#saveBook').disabled=!canEditBook;$('#bookTitle').disabled=!canEditBook;$('#bookAuthor').disabled=!canEditBook;$('#bookMode').textContent=state.club.pending_mode==='why'?'porque quiero':pending?'prompt activo':'bloqueado';if(state.club.pending_mode==='spin'&&currentPrompt){$('#resultNum').textContent=currentPrompt.id;$('#resultTitle').textContent=currentPrompt.title;$('#resultText').textContent=currentPrompt.description}else if(state.club.pending_mode==='why'){$('#resultNum').textContent='★';$('#resultTitle').textContent='Porque quiero';$('#resultText').textContent='La ruleta queda fuera de esta ronda. Escribe el libro que quieres leer.'}else{$('#resultNum').textContent='—';$('#resultTitle').textContent='Todavía no hay prompt';$('#resultText').textContent='Cuando gires, el resultado quedará registrado y ese prompt saldrá de la ruleta.'}renderHistory()}
async function animateChosen(chosenId,beforeItems){const idx=beforeItems.findIndex(p=>p.id===Number(chosenId));if(idx<0||!beforeItems.length)return;const slice=360/beforeItems.length,desired=(360-(idx*slice+slice/2))%360,mod=((rotation%360)+360)%360,delta=2160+((desired-mod+360)%360);rotation+=delta;$('#wheel').style.transform=`rotate(${rotation}deg)`;await new Promise(r=>setTimeout(r,4900))}
async function doSpin(){busy=true;render();const before=availablePrompts().slice();try{const chosen=await rpc('spin_wheel',{p_session:sessionToken});if(chosen?.id)await animateChosen(chosen.id,before);await loadState(true)}catch(e){fail(e);await loadState(false)}finally{busy=false;render()}}
async function doNope(){busy=true;render();const before=availablePrompts().slice();try{const chosen=await rpc('use_nope_and_spin',{p_session:sessionToken});if(chosen?.id)await animateChosen(chosen.id,before);await loadState(true)}catch(e){fail(e);await loadState(false)}finally{busy=false;render()}}
async function simpleAction(fnName){busy=true;render();try{await rpc(fnName,{p_session:sessionToken});await loadState(true)}catch(e){fail(e);await loadState(false)}finally{busy=false;render()}}
$('#spinBtn').onclick=()=>modal('¿Girar la ruleta?','El resultado será definitivo, quedará en el historial y ese prompt saldrá de la ruleta.',doSpin);$('#nopeBtn').onclick=()=>modal('¿Usar NOPE?','El prompt actual quedará descartado, el comodín se gastará y la ruleta girará otra vez en este mismo turno.',doNope);$('#whyBtn').onclick=()=>modal('¿Usar PORQUE QUIERO?','Se gastará el comodín y se desbloqueará el cuadro para escribir directamente el libro.',()=>simpleAction('use_why'));$('#decideBtn').onclick=()=>modal('¿Usar TÚ DECIDES?','El comodín se gastará y el turno pasará inmediatamente a la otra persona.',()=>simpleAction('use_decide'));
$('#saveBook').onclick=()=>{const title=$('#bookTitle').value.trim(),author=$('#bookAuthor').value.trim();if(!title||!author){alert('Escribe título y autor antes de guardar.');return}modal('¿Guardar este libro?',`“${title}” — ${author}. Una vez guardado quedará bloqueado y el turno cambiará.`,async()=>{busy=true;render();try{await rpc('save_book',{p_session:sessionToken,p_title:title,p_author:author});$('#bookTitle').value='';$('#bookAuthor').value='';await loadState(true)}catch(e){fail(e);await loadState(false)}finally{busy=false;render()}})};
async function boot(){if(!client)return;const saved=localStorage.getItem('entre_paginas_session');if(saved){try{const p=await rpc('session_profile',{p_session:saved});sessionToken=saved;me=p;await enterApp();return}catch{localStorage.removeItem('entre_paginas_session')}}showAuth(true);await refreshAuthMode()}boot();
