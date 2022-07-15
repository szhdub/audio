<template>
  <!-- <div class="test">
    <button onclick="">测试</button>
  </div> -->

<div id="demo">
  Push this button to do something you shouldn't be doing:<br>

  <div :class="{ shake: noActivated }">
    <button @click="noActivated = true">Click me</button>
    <span v-if="noActivated">Oh no!</span>
  </div>
</div>

</template>

<script>
import { defineComponent } from '@vue/composition-api'

export default defineComponent({
  setup() {
    
  },
})
</script>


// <script>
//   export default {
//     data() {
//       return {
//         websock: null,
//       }
//     },
//     methods: {
//       // 初始化weosocket
//       initWebSocket(){ 
//         if(typeof(WebSocket) === "undefined"){
//           console.log("您的浏览器不支持WebSocket")
//         }else{
//           const wsurl = "ws://121.40.165.18:8800";
//           // 实例化 WebSocket
//           this.websock = new WebSocket(wsurl);
//           // 监听 WebSocket 连接
//           this.websock.onopen = this.websocketonopen;
//           // 监听 WebSocket 错误信息
//           this.websock.onerror = this.websocketonerror;
//           // 监听 WebSocket 消息
//           this.websock.onmessage = this.websocketonmessage;
        
//           this.websock.onclose = this.websocketclose;
//         }
//       },
//       // 连接建立之后执行send方法发送数据
//       websocketonopen(){
//         console.log("socket连接成功")
//         let actions = {"test":"12345"};
//         this.websocketsend(JSON.stringify(actions));
//       },
//       // 连接建立失败重连
//       websocketonerror(){
//         console.log("连接错误");
//         this.initWebSocket();
//       },
//       // 数据接收
//       websocketonmessage(e){
//         const resdata = JSON.parse(e.data);
//         console.log(resdata);
//       },
//       // 数据发送
//       websocketsend(Data){
//         this.websock.send(Data);
//       },
//       // 关闭
//       websocketclose(e){
//         console.log('WebSocket 断开连接',e);
//       },
//     },    
//     beforeMount() {
//       this.initWebSocket();
//     },
//     unmounted() {
//       //离开路由之后断开 websocket 连接
//       this.websock.close(); 
//     },
//   }
// </script>

// <script>
//     let socket = null;
//     let lockReconnet = false; //避免重复连接
//     const wsUrl = 'ws://121.40.165.18:8800';
//     let createSocket = url=>{ //创建socket
//      try{
//      if('WebSocket' in window){
//      socket = new WebSocket(url)
//      }else if('MozWebSocket' in window){
//      socket = new MozWebSocket(url)
//      }
//      initSocket()
//      }catch(e){
//      reconnet(url)
//      }
//     }
//     let initSocket = ()=>{ //初始化websocket
//      socket.onopen = ()=>{
//      console.log('socket连接成功')
//      //heartCheck.reset().start() //后端说暂时不需要做心跳检测
     
//      }
     
//      socket.onmessage = (ev)=>{
//      console.log(ev,'连接正常')
//      //heartCheck.reset().start() //后端说暂时不需要做心跳检测
//      }
     
//      socket.onerror = ()=>{
//      console.log('websocket服务出错了---onerror');
//      reconnet(wsUrl)
//      }
     
//      socket.onclose = ()=>{
//      console.log('websocket服务关闭了+++onclose');
//      reconnet(wsUrl)
//      }
//     }

//     let reconnet = url=>{ //重新连接websock函数
//      if(lockReconnet)
//      return false
//      lockReconnet = true
//      setTimeout(()=>{
//      createSocket(url)
//      lockReconnet = false
//      },2000)
//     }

//     let heartCheck = { //心跳检测
//      timeout: 60*1000,
//      timeoutObj: null,
//      serverTimeoutObj: null,
//      reset(){
//      clearTimeout(this.timeoutObj)
//      clearTimeout(this.serverTimeoutObj)
//      return this;
//      },
//      start(){
//      let that = this;
//      this.timeoutObj = setTimeout(()=>{
//      //发送数据，如果onmessage能接收到数据，表示连接正常,然后在onmessage里面执行reset方法清除定时器
//      socket.send('heart check')
//      this.serverTimeoutObj = setTimeout(()=>{
//      socket.close()
//      },that.timeout)
//      },this.timeout)
//      }
//     }

// </script>
