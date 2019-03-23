var resizeAllGridItems = function resizeAllGridItems(){
  if (!$('.tiles-grid')) {return;};
  var grid =  $('.tiles-grid');
  var rowHeight = parseInt($('.tiles-grid').css('grid-auto-rows'));
  var rowGap = parseInt($('.tiles-grid').css('grid-row-gap'));
  $('.tiles-grid-item').each(function() {
    var itemHeight = parseInt($(this).children('.tiles-grid-item-content').outerHeight(true));
    var rowSpan = Math.ceil((itemHeight + rowGap)/(rowHeight + rowGap));
      $(this).css('grid-row-end' ,("span " + rowSpan));
  });
};

window.onload = resizeAllGridItems();
window.addEventListener("resize", resizeAllGridItems);

export {resizeAllGridItems};
