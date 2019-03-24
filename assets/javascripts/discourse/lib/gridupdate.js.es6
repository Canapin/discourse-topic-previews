window.addEventListener("resize", resizeAllGridItems);
window.addEventListener("scroll", resizeAllGridItems);

function resizeGridItem(item, grid, rowHeight, rowGap){
  const contentHeight = item.querySelector('.tiles-grid-item-content').getBoundingClientRect().height
  const rowSpan = Math.ceil((contentHeight+rowGap)/(rowHeight+rowGap));
  item.style.gridRowEnd = "span "+rowSpan;
}

function resizeAllGridItems(){
  const allItems = document.getElementsByClassName("tiles-grid-item");
  const grid = document.getElementsByClassName("tiles-grid")[0];
  if (!grid) {return;};
  const rowHeight = parseInt(window.getComputedStyle(grid).getPropertyValue('grid-auto-rows'));
  const rowGap = parseInt(window.getComputedStyle(grid).getPropertyValue('grid-row-gap'));
  for(var x=0;x<allItems.length;x++){
    resizeGridItem(allItems[x], grid, rowHeight, rowGap);
  }
}

export {resizeAllGridItems};
