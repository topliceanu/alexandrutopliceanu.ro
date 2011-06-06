/* 
	Author: Alexandru Topliceanu
*/
$(function(){
	$('p.row')
		.bind( 'mouseover', function( ev ){
			$(this).children('.left').css({'visibility':'visible'}) ;
		})
		.bind( 'mouseout', function( ev ){
			$(this).children('.left').css({'visibility':'hidden'}) ;
		}) ;
}) ;
