import QtQuick
Canvas {
    id:f
    property color fill: Theme.primary
    property int lobes: 10
    property real depth: 0.08
    property real phase: 0
    onPhaseChanged: requestPaint()
    onDepthChanged: requestPaint()
    onLobesChanged: requestPaint()
    onFillChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c=getContext("2d"); c.reset(); c.clearRect(0,0,width,height);
        const angleStep=Math.PI/180;
        const centerX=width*.5; const centerY=height*.5;
        const radiusBase=Math.min(width,height)*Math.min(1,.5/(.46+depth*.5));
        const offset=phase*Math.PI/180;
        c.beginPath();
        for(let i=0;i<=360;i++) {
            const a=i*angleStep;
            const cosine=Math.cos(a); const sine=Math.sin(a);
            const r=radiusBase*(.46+depth*.5*Math.cos(lobes*(a-offset)));
            const x=centerX+cosine*r; const y=centerY+sine*r;
            if(i===0)c.moveTo(x,y);else c.lineTo(x,y);
        }
        c.closePath(); c.fillStyle=fill; c.fill();
    }
}
