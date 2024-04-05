using UnityEngine;
using UnityEditor;

public partial class PostFXStack
{

    partial void applySceneViewState();

#if UNITY_EDITOR

    //�����ǰ������ͼ����ͼ���������Ǿͽ���ջ
    partial void applySceneViewState()
    {
        if(camera.cameraType == CameraType.SceneView && !SceneView.currentDrawingSceneView.sceneViewState.showImageEffects)
        {
            postFXSetting = null;
        }
    }

#endif

}
