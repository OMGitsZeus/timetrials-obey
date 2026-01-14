const hud = document.getElementById("hud");
const comboScore = document.getElementById("comboScore");
const multiplier = document.getElementById("multiplier");
const bankedTotal = document.getElementById("bankedTotal");
const speed = document.getElementById("speed");
const angle = document.getElementById("angle");
const angleBar = document.getElementById("angleBar");
const collision = document.getElementById("collision");
const stopCountdown = document.getElementById("stopCountdown");
const stopCountdownValue = stopCountdown.querySelector("span");

const summary = document.getElementById("summary");
const summaryTotal = document.getElementById("summaryTotal");
const summaryCombo = document.getElementById("summaryCombo");
const summaryAngle = document.getElementById("summaryAngle");
const summaryDuration = document.getElementById("summaryDuration");
const summaryStatus = document.getElementById("summaryStatus");

let lastMultiplier = "x1";

const formatNumber = (value) => {
  return Math.floor(value).toLocaleString("en-US");
};

window.addEventListener("message", (event) => {
  const data = event.data;

  if (data.type === "drift:show") {
    hud.classList.toggle("hidden", !data.show);
    if (!data.show) {
      stopCountdown.classList.remove("show");
      collision.classList.remove("show");
    }
  }

  if (data.type === "drift:update") {
    comboScore.textContent = formatNumber(data.combo || 0);
    bankedTotal.textContent = formatNumber(data.total || 0);
    speed.textContent = `${Math.round(data.speed || 0)} ${data.speedUnit || "mph"}`;
    angle.textContent = `${Math.round(data.angle || 0)}°`;
    angleBar.style.width = `${Math.min(100, Math.max(0, data.anglePercent || 0))}%`;

    const nextMultiplier = data.multiplier || "x1";
    if (nextMultiplier !== lastMultiplier) {
      multiplier.classList.add("bump");
      setTimeout(() => multiplier.classList.remove("bump"), 200);
      lastMultiplier = nextMultiplier;
    }
    multiplier.textContent = nextMultiplier;
  }

  if (data.type === "drift:collision") {
    collision.classList.add("show");
    setTimeout(() => collision.classList.remove("show"), 800);
  }

  if (data.type === "drift:countdown") {
    if (data.show) {
      stopCountdown.classList.add("show");
      stopCountdownValue.textContent = data.seconds || 0;
    } else {
      stopCountdown.classList.remove("show");
    }
  }

  if (data.type === "drift:summary") {
    summary.classList.toggle("hidden", !data.show);
    if (data.show) {
      summaryTotal.textContent = formatNumber(data.total || 0);
      summaryCombo.textContent = formatNumber(data.bestCombo || 0);
      summaryAngle.textContent = `${Math.round(data.bestAngle || 0)}°`;
      summaryDuration.textContent = `${Math.round(data.duration || 0)}s`;
      summaryStatus.textContent = data.status || "Saved";
    }
  }
});
