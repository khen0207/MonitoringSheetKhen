# patch-index.ps1
# Run this INSIDE the MonitoringSheetKhen folder (same folder as index.html).
# It makes a backup (index.html.backup) and then adds: Firebase + admin login + view-only for visitors.

$path = Join-Path (Get-Location) "index.html"
if (-not (Test-Path $path)) {
  Write-Host "index.html not found. Open the terminal inside your project folder and try again." -ForegroundColor Red
  exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$t = [System.IO.File]::ReadAllText($path, $utf8)

if ($t.Contains("let canEdit=false;")) {
  Write-Host "index.html is already patched. Nothing to do." -ForegroundColor Yellow
  exit 0
}

Copy-Item $path "$path.backup" -Force
Write-Host "Backup saved as index.html.backup" -ForegroundColor Cyan

$allOk = $true

function Rep([string]$old, [string]$new) {
  if ($script:t.Contains($old)) {
    $script:t = $script:t.Replace($old, $new)
    Write-Host ("OK   " + $old) -ForegroundColor Green
  } else {
    Write-Host ("MISSING   " + $old) -ForegroundColor Red
    $script:allOk = $false
  }
}

# ---- Edit 1: Firebase scripts (placed above the main <script>) ----
$scripts = @'
<script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore-compat.js"></script>
'@
$i = $t.IndexOf("const DATA=[")
if ($i -lt 0) {
  Write-Host "MISSING   const DATA=[" -ForegroundColor Red
  $allOk = $false
} else {
  $j = $t.LastIndexOf("<script>", $i)
  $t = $t.Insert($j, $scripts + "`n")
  Write-Host "OK   Firebase script tags" -ForegroundColor Green
}

# ---- Edit 2: permissions ----
Rep 'const P=()=>({sched:true,att:true});' 'const P=()=>({sched:canEdit,att:canEdit});'

# ---- Edit 3: guards ----
Rep 'function mark(k,f,v){' 'function mark(k,f,v){if(!canEdit)return;'
Rep 'function markAll(a){' 'function markAll(a){if(!canEdit)return;'
Rep 'function newS(){' 'function newS(){if(!canEdit)return;'
Rep 'function add(){' 'function add(){if(!canEdit)return;'

# ---- Edit 4: header with Admin login / Log out ----
$navNew = @'
document.getElementById("who").innerHTML="Fernan Valenzuela &middot; "+(canEdit?'Signed in &middot; <a href="#" onclick="logout();return false" style="color:#fde68a">Log out</a>':'View only &middot; <a href="#" onclick="login();return false" style="color:#fde68a">Admin login</a>')}
'@
$navNew = $navNew.Trim()
$navPattern = 'document\.getElementById\("who"\)\.textContent=db\?"[^"]*":"Fernan Valenzuela "\}'
if ([regex]::IsMatch($t, $navPattern)) {
  $t = [regex]::Replace($t, $navPattern, $navNew)
  Write-Host "OK   header (Admin login / Log out)" -ForegroundColor Green
} else {
  Write-Host "MISSING   header line (who)" -ForegroundColor Red
  $allOk = $false
}

# ---- Edit 5: lock the table when view-only ----
Rep 'app.innerHTML=tab=="dash"?dash():tab=="emp"?emp():ses();' 'app.innerHTML=tab=="dash"?dash():tab=="emp"?emp():ses();lock();'

# ---- Edit 6: replace the last block (Firebase init, login, lock) ----
$newBlock = @'
let canEdit=false;
const OWNER="khenvalenzuela0@gmail.com";

function lock(){
  if(canEdit)return;
  document.querySelectorAll("#app table select,#app table input").forEach(el=>el.disabled=true);
  document.querySelectorAll("#app details.tools").forEach(el=>el.style.display="none");
}

function login(){
  if(document.getElementById("lg"))return;
  const d=document.createElement("div");
  d.id="lg";
  d.style.cssText="position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:99";
  d.innerHTML='<div class="box" style="min-width:260px"><h2>Admin login</h2><div class="tools" style="flex-direction:column"><input id="le" type="email" placeholder="Email"><input id="lp" type="password" placeholder="Password"><button class="b p" id="lgo">Login</button><button class="b" id="lcx">Cancel</button><div id="lerr" class="sub"></div></div></div>';
  document.body.appendChild(d);
  document.getElementById("lcx").onclick=()=>d.remove();
  document.getElementById("lgo").onclick=()=>{
    firebase.auth().signInWithEmailAndPassword(document.getElementById("le").value.trim(),document.getElementById("lp").value)
      .then(()=>d.remove())
      .catch(e=>document.getElementById("lerr").textContent="Login failed: "+e.code);
  };
}
function logout(){firebase.auth().signOut()}

(() => {
  refresh();
  render();
  try{
    firebase.initializeApp({
      apiKey:"AIzaSyB353pxS0ImC9faSAwKZvaf4KVYOqTmbFk",
      authDomain:"monitoringsheetkhen.firebaseapp.com",
      projectId:"monitoringsheetkhen",
      storageBucket:"monitoringsheetkhen.firebasestorage.app",
      messagingSenderId:"872029396614",
      appId:"1:872029396614:web:5c91dff5c146fa1e457b07"
    });
    const fdb=firebase.firestore();
    db=fdb;
    M={};X=[];SS=[];
    fdb.collection("marks").onSnapshot(s=>{M={};s.docs.forEach(d=>M[d.id]=d.data());refresh();render()},()=>{});
    fdb.collection("extra").onSnapshot(s=>{X=s.docs.map(d=>({k:"x"+d.id,...d.data()}));refresh();render()},()=>{});
    fdb.collection("sessions").onSnapshot(s=>{SS=s.docs.map(d=>d.data().label).filter(Boolean);render()},()=>{});
    firebase.auth().onAuthStateChanged(u=>{canEdit=!!u&&u.email===OWNER;render()});
  }catch(e){console.error(e)}
})();
'@
$s = $t.LastIndexOf("(() => {")
$e = $t.LastIndexOf("</script>")
if ($s -lt 0 -or $e -lt 0 -or $s -gt $e) {
  Write-Host "MISSING   final script block" -ForegroundColor Red
  $allOk = $false
} else {
  $t = $t.Substring(0, $s) + $newBlock + "`n" + $t.Substring($e)
  Write-Host "OK   final script block" -ForegroundColor Green
}

# ---- Save ----
if ($allOk) {
  [System.IO.File]::WriteAllText($path, $t, $utf8)
  Write-Host ""
  Write-Host "DONE! index.html is patched." -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "Some parts were not found, so NOTHING was changed. Your original index.html is untouched." -ForegroundColor Red
  Write-Host "Tell me which lines say MISSING." -ForegroundColor Red
}
