var resizeAllGridItems = function resizeAllGridItems(){
  const grid = document.getElementsByClassName("tiles-grid")[0];
  if (!grid) {return;};
  const rowHeight = parseInt(window.getComputedStyle(grid).getPropertyValue('grid-auto-rows'));
  const rowGap = parseInt(window.getComputedStyle(grid).getPropertyValue('grid-row-gap'));
  var allItems = document.getElementsByClassName("tiles-grid-item");
  var x=0;
  for(x=0;x<allItems.length;x++){
    var thisHeight = allItems[x].querySelector('.tiles-grid-item-content').getBoundingClientRect().height
    var rowSpan = Math.ceil((thisHeight+rowGap)/(rowHeight+rowGap));
    allItems[x].style.gridRowEnd = "span "+rowSpan;
   }
};

window.onload = resizeAllGridItems();
window.addEventListener("resize", resizeAllGridItems);
window.addEventListener("scroll", resizeAllGridItems);

export {resizeAllGridItems};
