(() => {
  const recover = (image) => {
    if (!(image instanceof HTMLImageElement) || !image.closest(".insights-author-image")) return;
    if (image.complete && image.naturalWidth === 0) image.hidden = true;
  };
  document.addEventListener("error", (event) => recover(event.target), true);
  document.querySelectorAll(".insights-author-image img").forEach(recover);
})();
