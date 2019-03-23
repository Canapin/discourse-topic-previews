var resizeAllGridItems = function resizeAllGridItems(){
  const grid = $('.tiles-grid');
  if (!grid) {return;};
  const rowHeight = parseInt(grid.css('grid-auto-rows'));
  const rowGap = parseInt(grid.css('grid-row-gap'));
  $('.tiles-grid-item').each(function() {
    var itemHeight = parseInt($(this).children('.tiles-grid-item-content').outerHeight(true));
    var rowSpan = Math.ceil((itemHeight + rowGap)/(rowHeight + rowGap));
      $(this).css('grid-row-end' ,("span " + rowSpan));
  });
};

window.onload = resizeAllGridItems();
window.addEventListener("resize", resizeAllGridItems);
window.addEventListener("scroll", resizeAllGridItems);

export {resizeAllGridItems};
