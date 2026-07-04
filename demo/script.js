const connect = document.getElementById('connect');
const wallet = document.getElementById('wallet');
const pool = document.getElementById('pool');
const amount = document.getElementById('amount');
const swapBtn = document.getElementById('swapBtn');
const analysis = document.getElementById('analysis');
const risk = document.getElementById('risk');
const fee = document.getElementById('fee');
const signature = document.getElementById('signature');
const executed = document.getElementById('executed');
const updated = document.getElementById('updated');
const amountInput = document.getElementById('amountInput');
const steps = Array.from(document.querySelectorAll('.timeline-item'));

function stepById(id){return document.getElementById(id)}

function setActiveStep(step){
  steps.forEach(item => item.classList.toggle('active', item.id === step));
}

connect.onclick = () => {
  document.getElementById('actions').classList.remove('hidden');
  document.getElementById('pool').classList.remove('hidden');
  document.getElementById('amount').classList.remove('hidden');
  swapBtn.classList.remove('hidden');
  connect.disabled = true;
  connect.innerText = 'Connected';
  markComplete('step-wallet');
  setActiveStep('step-wallet');
};

function animateNumber(el, target, speed = 20) {
  let cur = 0;
  clearInterval(el._int);
  el._int = setInterval(() => {
    cur++;
    el.innerText = cur;
    if (cur >= target) clearInterval(el._int);
  }, speed);
}

async function runDemoFlow() {
  markComplete('step-submitted');
  setActiveStep('step-analysis');
  document.getElementById('step-analysis').classList.add('running');

  // simulate small delay
  await new Promise((r) => setTimeout(r, 600));

  // finish analysis
  markComplete('step-analysis');
  await new Promise((r) => setTimeout(r, 200));
  // show risk and fee will be handled by caller
}

swapBtn.onclick = async () => {
  // optionally call backend analysis
  const payload = {
    pool: 'ETH-USDC',
    amount: Number(amountInput.value || 1000)
  };

  // show analysis and run demo flow
  markComplete('step-pool');
  markComplete('step-amount');
  setActiveStep('step-submitted');
  markComplete('step-submitted');
  // show analysis spinner
  document.getElementById('step-analysis').querySelector('.spinner-inline').classList.remove('hidden');

  let data = null;
  try {
    const resp = await fetch('/api/analyze', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (resp.ok) data = await resp.json();
  } catch (e) {
    // ignore
  }

  // run base demo flow (analysis -> risk)
  await runDemoFlow();

  const riskScore = data && data.riskScore ? data.riskScore : 82;
  setActiveStep('step-risk');
  animateNumber(document.querySelector('#step-risk .score'), riskScore, 12);
  markComplete('step-risk');

  // fee
  const recommended = data && data.recommendedSpread ? data.recommendedSpread : 9000;
  setActiveStep('step-fee');
  document.querySelector('#step-fee .percent').innerText = (recommended / 10000).toFixed(2) + '%';
  markComplete('step-fee');

  // signature
  const verified = data && typeof data.verified !== 'undefined' ? data.verified : true;
  if (verified) {
    setActiveStep('step-signature');
    markComplete('step-signature');
  }

  // sending + executed
  await new Promise((r) => setTimeout(r, 400));
  setActiveStep('step-sending');
  markComplete('step-sending');
  await new Promise((r) => setTimeout(r, 600));
  setActiveStep('step-executed');
  markComplete('step-executed');
  await new Promise((r) => setTimeout(r, 400));
  setActiveStep('step-updated');
  markComplete('step-updated');
};

steps.forEach(item => {
  item.addEventListener('click', () => {
    const id = item.id;
    if (!document.getElementById(id).classList.contains('complete')) {
      setActiveStep(id);
      return;
    }
    setActiveStep(id);
  });
});

function markComplete(id){
  const el = document.getElementById(id);
  if(!el) return;
  el.classList.add('complete');
  const chk = el.querySelector('.check');
  if(chk) chk.classList.remove('hidden');
}
