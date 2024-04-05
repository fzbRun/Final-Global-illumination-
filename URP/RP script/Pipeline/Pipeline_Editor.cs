using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.GlobalIllumination;
using LightType = UnityEngine.LightType;

public partial class Pipeline : RenderPipeline
{

    partial void InitializeForEditor();
    partial void DisposeForEditor();

#if UNITY_EDITOR
    static Lightmapping.RequestLightsDelegate lightDelefate =
    (Light[] lights, NativeArray<LightDataGI> output) =>
    {
        var lightData = new LightDataGI();  //������Ӧ��Դ�������˵Ľṹ
        for(int i = 0; i < lights.Length; i++)
        {
            Light light = lights[i];
            switch (light.type) {
                case LightType.Directional:
                    var directionalLight = new DirectionalLight();
                    LightmapperUtils.Extract(light, ref directionalLight);  //��ȡ��Դ��Ϣ
                    lightData.Init(ref directionalLight);   //���ù�Դ��Ϣ��ʼ���ṹ
                    break;
                case LightType.Point:
                    var pointLight = new PointLight();
                    LightmapperUtils.Extract(light, ref pointLight);
                    lightData.Init(ref pointLight);
                    break;
                case LightType.Spot:
                    var spotLight = new SpotLight();
                    LightmapperUtils.Extract(light, ref spotLight); //��ȡ��Դ��Ϣ��spotLight�У������������ǣ�������Ҫ�ֶ���ֵ
                    spotLight.innerConeAngle =  //�ֶ����������
                            light.innerSpotAngle * Mathf.Deg2Rad;
                    spotLight.angularFalloff =
                        AngularFalloffType.AnalyticAndInnerAngle;
                    lightData.Init(ref spotLight);
                    break;
                case LightType.Area:
                    var rectangleLight = new RectangleLight();
                    LightmapperUtils.Extract(light, ref rectangleLight);
                    rectangleLight.mode = LightMode.Baked;  //��֧��ʵʱ����⣬ֻ�ܺ���
                    lightData.Init(ref rectangleLight);
                    break;
                default:
                    lightData.InitNoBake(light.GetInstanceID());    //��ʼ���ṹ���ǲ�����
                    break;
            }
            lightData.falloff = FalloffType.InverseSquared; //����˥��
            output[i] = lightData;
        }
    };

    partial void InitializeForEditor()
    {
        Lightmapping.SetDelegate(lightDelefate);
    }

    protected void DisposeForEditor(bool disposing)
    {
        Lightmapping.ResetDelegate();
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        DisposeForEditor(disposing);
        renderer.Dispose(); //ֻ�ڱ༭����ɾ������Ϊ����ʱ��Ҫһֱʹ�ã�����Ҫɾ����
    }

#endif

}
