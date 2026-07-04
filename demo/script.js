const connect = document.getElementById('connect');
const swapBtn = document.getElementById('swapBtn');
const amountInput = document.getElementById('amountInput');
const statusBadge = document.getElementById('statusBadge');
const cardRisk = document.getElementById('cardRisk');
const cardFee = document.getElementById('cardFee');
const cardSignature = document.getElementById('cardSignature');
const transactionAmount = document.getElementById('transactionAmount');
const steps = Array.from(document.querySelectorAll('.timeline-item'));

function setActiveStep(step) {
  steps.forEach(item => item.classList.toggle('active', item.id === step));
}

function setCardStatus(text, tone = 'default') {
  if (!statusBadge) return;
  statusBadge.innerText = text;
  statusBadge.className = 'status-pill';
  if (tone === 'danger') statusBadge.classList.add('danger');
  if (tone === 'accent') statusBadge.classList.add('accent');
}

function updateCardDetails(payload = {}) {
  if (transactionAmount) {
    const amount = Number(amountInput?.value || payload.amount || 1000);
    transactionAmount.innerText = amount.toLocaleString();
  }
  if (payload.risk !== undefined && cardRisk) {
    cardRisk.innerText = payload.risk;
  }
  if (payload.fee !== undefined && cardFee) {
    cardFee.innerText = payload.fee;
  }
  if (payload.signature !== undefined && cardSignature) {
    cardSignature.innerText = payload.signature;
  }
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
  setCardStatus('Wallet linked', 'accent');
  updateCardDetails();
};

function animateNumber(el, target, speed = 20) {
  let cur = 0;
  clearInterval(el._int);
  el._int = setInterval(() => {
    cur += 1;
    el.innerText = cur;
    if (cur >= target) clearInterval(el._int);
  }, speed);
}

async function runDemoFlow() {
  markComplete('step-submitted');
  setActiveStep('step-analysis');
  document.getElementById('step-analysis').classList.add('running');
  setCardStatus('Analyzing threat', 'accent');

  await new Promise((r) => setTimeout(r, 600));
  markComplete('step-analysis');
  await new Promise((r) => setTimeout(r, 200));
}

swapBtn.onclick = async () => {
  const payload = {
    pool: 'ETH-USDC',
    amount: Number(amountInput.value || 1000)
  };

  markComplete('step-pool');
  markComplete('step-amount');
  setActiveStep('step-submitted');
  markComplete('step-submitted');
  updateCardDetails(payload);
  setCardStatus('Submitting swap', 'accent');
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

  await runDemoFlow();

  const riskScore = data && typeof data.riskScore !== 'undefined' ? data.riskScore : 82;
  setActiveStep('step-risk');
  animateNumber(document.querySelector('#step-risk .score'), riskScore, 12);
  markComplete('step-risk');

  const recommended = data && data.feePercent ? data.feePercent : '0.90%';
  setActiveStep('step-fee');
  document.querySelector('#step-fee .percent').innerText = recommended;
  markComplete('step-fee');

  const verified = data && typeof data.verified !== 'undefined' ? data.verified : true;
  if (verified) {
    setActiveStep('step-signature');
    markComplete('step-signature');
  }

  updateCardDetails({
    risk: `${riskScore}/100`,
    fee: recommended,
    signature: verified ? 'Verified' : 'Pending'
  });
  setCardStatus(verified ? 'Threat profile ready' : 'Waiting on signature', verified ? 'accent' : 'danger');

  await new Promise((r) => setTimeout(r, 400));
  setActiveStep('step-sending');
  markComplete('step-sending');
  await new Promise((r) => setTimeout(r, 600));
  setActiveStep('step-executed');
  markComplete('step-executed');
  await new Promise((r) => setTimeout(r, 400));
  setActiveStep('step-updated');
  markComplete('step-updated');
  setCardStatus('LP fee updated', 'accent');
};

steps.forEach(item => {
  item.addEventListener('click', () => {
    setActiveStep(item.id);
  });
});

function markComplete(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.add('complete');
  const chk = el.querySelector('.check');
  if (chk) chk.classList.remove('hidden');
}

updateCardDetails();
