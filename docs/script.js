/**
 * LiveSub Landing Page Interactive Controller
 */

document.addEventListener("DOMContentLoaded", () => {
  // 1. Interactive Demo Subtitle Switcher
  const demoSnippets = [
    {
      srcFlag: "🇯🇵",
      srcLang: "JA",
      tgtFlag: "🇺🇸",
      tgtLang: "EN",
      text: "“I won’t give up, that’s my ninja way!”",
      original: "諦めない、それが俺の忍道だ！"
    },
    {
      srcFlag: "🇫🇷",
      srcLang: "FR",
      tgtFlag: "🇺🇸",
      tgtLang: "EN",
      text: "“In life, you have to seize every opportunity.”",
      original: "Dans la vie, il faut saisir chaque opportunité."
    },
    {
      srcFlag: "🇪🇸",
      srcLang: "ES",
      tgtFlag: "🇺🇸",
      tgtLang: "EN",
      text: "“Where words fail, music speaks.”",
      original: "Donde las palabras fallan, la música habla."
    },
    {
      srcFlag: "🇰🇷",
      srcLang: "KO",
      tgtFlag: "🇺🇸",
      tgtLang: "EN",
      text: "“Let’s meet again when the cherry blossoms bloom.”",
      original: "벚꽃이 피면 다시 만나요."
    }
  ];

  let currentSnippetIndex = 0;
  const demoSrcEl = document.getElementById("demo-src");
  const demoTgtEl = document.getElementById("demo-tgt");
  const demoTextEl = document.getElementById("demo-text");

  if (demoTextEl) {
    setInterval(() => {
      currentSnippetIndex = (currentSnippetIndex + 1) % demoSnippets.length;
      const snippet = demoSnippets[currentSnippetIndex];
      
      demoTextEl.style.opacity = "0";
      demoTextEl.style.transform = "translateY(4px)";
      
      setTimeout(() => {
        demoSrcEl.textContent = `${snippet.srcFlag} ${snippet.srcLang}`;
        demoTgtEl.textContent = `${snippet.tgtFlag} ${snippet.tgtLang}`;
        demoTextEl.textContent = snippet.text;
        
        demoTextEl.style.transition = "all 0.3s ease";
        demoTextEl.style.opacity = "1";
        demoTextEl.style.transform = "translateY(0)";
      }, 300);
    }, 4000);
  }

  // 2. FAQ Accordion
  const faqItems = document.querySelectorAll(".faq-item");
  faqItems.forEach(item => {
    const questionBtn = item.querySelector(".faq-question");
    questionBtn.addEventListener("click", () => {
      const isActive = item.classList.contains("active");
      faqItems.forEach(otherItem => otherItem.classList.remove("active"));
      if (!isActive) {
        item.classList.add("active");
      }
    });
  });

  // 3. Waitlist Form Submission
  const waitlistForms = document.querySelectorAll(".waitlist-form");
  waitlistForms.forEach(form => {
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const input = form.querySelector(".waitlist-input");
      const button = form.querySelector(".btn-submit");
      const email = input.value.trim();

      if (!email || !email.includes("@")) {
        alert("Please enter a valid email address.");
        return;
      }

      // Store in localStorage for demonstration/leads tracking
      let storedLeads = JSON.parse(localStorage.getItem("livesub_leads") || "[]");
      storedLeads.push({ email, timestamp: new Date().toISOString() });
      localStorage.setItem("livesub_leads", JSON.stringify(storedLeads));

      // Visual feedback
      const originalText = button.innerHTML;
      button.disabled = true;
      button.innerHTML = "<span>Joining...</span>";

      setTimeout(() => {
        form.innerHTML = `
          <div style="padding: 14px 20px; font-weight: 500; font-size: 0.95rem; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; width: 100%;">
            <span style="color: #10b981; font-weight: 600;">You're on the early access list.</span>
            <span style="color: #94a3b8; font-size: 0.88rem;">We'll email a TestFlight link to ${email} as spots open.</span>
          </div>
        `;
      }, 700);
    });
  });
});
